-- create database, schema and warehouse
create or replace database ecommerce_dw;

use database ecommerce_dw;

create or replace schema sales_schema;

use schema sales_schema;

create or replace warehouse ecommerce_wh
warehouse_size = 'xsmall'
auto_suspend = 60
auto_resume = true;

use warehouse ecommerce_wh;

-- create file format
create or replace file format csv_format
    type = 'csv'
    field_delimiter = ','
    skip_header = 1
    field_optionally_enclosed_by = '"'
    null_if = ('null', 'NULL');

-- upload these three files to this stage using the snowflake ui:
--
-- raw_orders.csv
-- raw_inventory.csv
-- raw_fulfillment.csv

create or replace stage ecommerce_stage
    file_format = csv_format;

-- create raw orders table
create or replace table raw_orders (
    order_id varchar(20),
    order_date date,
    user_id varchar(20),
    store_id varchar(20),
    amount number(10,2),
    tax number(10,2),
    payment_method varchar(50),
    shipping_option varchar(50),
    gift_wrap_flag varchar(1)
);

-- create raw inventory table
create or replace table raw_inventory (
    snapshot_date date,
    store_id varchar(20),
    product_id varchar(20),
    qty_on_hand number(10,0),
    unit_cost number(10,2)
);

-- create raw fulfillment table
create or replace table raw_fulfillment (
    order_id varchar(20),
    order_date date,
    pick_date date,
    ship_date date,
    delivery_date date
);

-- check files uploaded to stage
list @ecommerce_stage;

-- load raw orders csv
copy into raw_orders
from @ecommerce_stage/raw_orders.csv
file_format = csv_format
on_error = 'continue';

-- load raw inventory csv
copy into raw_inventory
from @ecommerce_stage/raw_inventory.csv
file_format = csv_format
on_error = 'continue';

-- load raw fulfillment csv
copy into raw_fulfillment
from @ecommerce_stage/raw_fulfillment.csv
file_format = csv_format
on_error = 'continue';

-- verify raw data
select * from raw_orders;

select * from raw_inventory;

select * from raw_fulfillment;

-- task 1: build junk dimension
create or replace table dim_order_indicators (
    indicator_sk number(10,0),
    payment_method varchar(50),
    shipping_option varchar(50),
    gift_wrap_flag varchar(1)
);

-- populate junk dimension
insert into dim_order_indicators(
indicator_sk,payment_method,shipping_option,gift_wrap_flag
)
select min(row_num) as indicator_sk,payment_method,shipping_option,gift_wrap_flag
from (select payment_method,shipping_option,gift_wrap_flag,
row_number() over (order by order_id) as row_num
from raw_orders
)
group by payment_method,shipping_option,gift_wrap_flag
order by indicator_sk;

-- verify junk dimension
select * from dim_order_indicators
order by indicator_sk;

-- task 2: build transaction fact table
create or replace table fact_sales_transactions (
    order_id varchar(20),
    order_date date,
    user_id varchar(20),
    store_id varchar(20),
    indicator_sk number(10,0),
    amount number(10,2),
    tax number(10,2)
);

-- populate transaction fact table
insert into fact_sales_transactions(
order_id,order_date,user_id,store_id,
indicator_sk,amount,tax
)
select r.order_id,r.order_date,r.user_id,r.store_id,d.indicator_sk,r.amount,r.tax
from raw_orders r
join dim_order_indicators d
on r.payment_method = d.payment_method
and r.shipping_option = d.shipping_option
and r.gift_wrap_flag = d.gift_wrap_flag;

-- verify transaction fact table
select order_id,indicator_sk,amount
from fact_sales_transactions
order by order_id;

-- task 3: build periodic snapshot fact table
create or replace table fact_inventory_snapshot (
    snapshot_date date,
    store_id varchar(20),
    total_units_held number(18,0),
    total_inventory_val number(18,2)
);

-- populate periodic snapshot fact table
insert into fact_inventory_snapshot(
snapshot_date,store_id,
total_units_held,total_inventory_val
)
select snapshot_date,store_id,
sum(qty_on_hand) as total_units_held,
sum(qty_on_hand * unit_cost) as total_inventory_val
from raw_inventory
group by snapshot_date,store_id;

-- verify periodic snapshot
select snapshot_date,store_id,total_units_held,total_inventory_val
from fact_inventory_snapshot
order by snapshot_date,store_id;

-- task 4: build accumulating snapshot fact table
create or replace table fact_order_fulfillment (
order_id varchar(20),order_date date,pick_date date,
ship_date date,delivery_date date,pick_lag_days number(10,0),
ship_lag_days number(10,0),delivery_lag_days number(10,0),total_fulfillment_days number(10,0)
);

-- populate accumulating snapshot
insert into fact_order_fulfillment(
order_id,order_date,pick_date,ship_date,delivery_date,pick_lag_days,
ship_lag_days,delivery_lag_days,total_fulfillment_days
)
select order_id,order_date,pick_date,ship_date,delivery_date,
datediff(day,order_date,pick_date) as pick_lag_days,
datediff(day,pick_date,ship_date) as ship_lag_days,
datediff(day,ship_date,delivery_date) as delivery_lag_days,
datediff(day,order_date,delivery_date) as total_fulfillment_days
from raw_fulfillment;

-- verify completed orders
select order_id,pick_lag_days,ship_lag_days,delivery_lag_days,total_fulfillment_days
from fact_order_fulfillment
where delivery_lag_days is not null
order by order_id;

-- task 5: incomplete lifecycle status auditing
select order_id,order_date,
case
when pick_date is not null and ship_date is null
then 'picked_not_shipped'
when ship_date is not null and delivery_date is null
then 'shipped_not_delivered'
when pick_date is null
then 'order_not_picked'
else 'unknown'
end as current_status
from fact_order_fulfillment
where delivery_date is null
order by order_id;

-- task 6: aggregate revenue by payment method
select d.payment_method,count(f.order_id) as total_orders,sum(f.amount) as total_revenue
from fact_sales_transactions f
join dim_order_indicators d
on f.indicator_sk = d.indicator_sk
group by d.payment_method
order by d.payment_method;

-- final verification
select * from dim_order_indicators
order by indicator_sk;

-- verify transaction fact
select order_id,indicator_sk,amount
from fact_sales_transactions
order by order_id;

-- verify inventory snapshot
select snapshot_date,store_id,total_units_held,total_inventory_val
from fact_inventory_snapshot
order by snapshot_date, store_id;

-- verify fulfillment snapshot
select order_id,pick_lag_days,ship_lag_days,delivery_lag_days,total_fulfillment_days
from fact_order_fulfillment
order by order_id;

-- verify incomplete orders
select order_id,order_date,
case
when pick_date is not null and ship_date is null
then 'picked_not_shipped'
when ship_date is not null and delivery_date is null
then 'shipped_not_delivered'
else 'unknown'
end as current_status
from fact_order_fulfillment
where delivery_date is null
order by order_id;

-- verify revenue summary
select d.payment_method,count(f.order_id) as total_orders,
sum(f.amount) as total_revenue
from fact_sales_transactions f
join dim_order_indicators d
on f.indicator_sk = d.indicator_sk
group by d.payment_method
order by d.payment_method;