-- phase 1 : snowflake setup
create warehouse if not exists retail_wh
warehouse_size = 'x-small'
auto_suspend = 60
auto_resume = true;

create database if not exists retail_dw;
create schema if not exists retail_dw.sales_schema;

use warehouse retail_wh;
use database retail_dw;
use schema sales_schema;


-- phase 2 : file format and stage
-- create csv format
create or replace file format csv_format
type = csv
skip_header = 1
field_optionally_enclosed_by = '"';

-- create internal stage
create or replace stage retail_stage
file_format = csv_format;

-- phase 3 : create dimensions
-- customer dimension
create or replace table dim_customer (
    customer_id number primary key,
    customer_name varchar,
    city varchar,
    state varchar,
    membership varchar
);

-- product dimension
create or replace table dim_product (
    product_id number primary key,
    product_name varchar,
    category varchar,
    brand varchar,
    price number(12,2)
);

-- branch dimension
create or replace table dim_branch (
    branch_id number primary key,
    branch_name varchar,
    city varchar,
    state varchar,
    region varchar,
    manager_name varchar
);

-- date dimension
create or replace table dim_date (
    date_id number primary key,
    date date,
    day number,
    day_name varchar,
    week_no number,
    month varchar,
    quarter varchar,
    year number,
    is_weekend varchar
);


-- phase 4 : create fact table
-- central fact table
create or replace table fact_sales (
    sale_id number primary key,
    customer_id number,
    product_id number,
    branch_id number,
    date_id number,
    quantity number,
    total_amount number(12,2)
);

-- phase 5 : upload and load data
-- upload csv files into @retail_stage using snowsight

copy into dim_customer
from @retail_stage/customers.csv
file_format = csv_format;

copy into dim_product
from @retail_stage/products.csv
file_format = csv_format;

copy into dim_branch
from @retail_stage/branches.csv
file_format = csv_format;

copy into dim_date
from @retail_stage/calendar.csv
file_format = csv_format;

copy into fact_sales
from @retail_stage/sales.csv
file_format = csv_format;

-- phase 6 : validate star schema
-- check row counts
select count(*) from dim_customer;
select count(*) from dim_product;
select count(*) from dim_branch;
select count(*) from dim_date;
select count(*) from fact_sales;

-- phase 7 : customer report
select c.customer_name,
       sum(f.total_amount) as revenue
from dim_customer c
join fact_sales f
on c.customer_id = f.customer_id
group by c.customer_name
order by revenue desc;

-- phase 8 : product report
select p.product_name,
       sum(f.total_amount) as revenue
from dim_product p
join fact_sales f
on p.product_id = f.product_id
group by p.product_name
order by revenue desc;

-- phase 9 : branch report
select b.branch_name,
       sum(f.total_amount) as revenue
from dim_branch b
join fact_sales f
on b.branch_id = f.branch_id
group by b.branch_name
order by revenue desc;

-- phase 10 : state-wise revenue
select b.state,
       sum(f.total_amount) as revenue
from dim_branch b
join fact_sales f
on b.branch_id = f.branch_id
group by b.state
order by revenue desc;

-- phase 11 : monthly revenue
select d.month,
       d.year,
       sum(f.total_amount) as revenue
from dim_date d
join fact_sales f
on d.date_id = f.date_id
group by d.month, d.year
order by d.year, d.month;

-- phase 12 : quarterly revenue
select d.quarter,
       d.year,
       sum(f.total_amount) as revenue
from dim_date d
join fact_sales f
on d.date_id = f.date_id
group by d.quarter, d.year;

-- phase 13 : top 10 customers
select c.customer_name,
       sum(f.total_amount) as revenue
from dim_customer c
join fact_sales f
on c.customer_id = f.customer_id
group by c.customer_name
order by revenue desc
limit 10;

-- phase 14 : top 10 products
select p.product_name,
       sum(f.total_amount) as revenue
from dim_product p
join fact_sales f
on p.product_id = f.product_id
group by p.product_name
order by revenue desc
limit 10;

-- phase 15 : top 10 branches
select b.branch_name,
       sum(f.total_amount) as revenue
from dim_branch b
join fact_sales f
on b.branch_id = f.branch_id
group by b.branch_name
order by revenue desc
limit 10;

-- phase 16 : category revenue
select p.category,
       sum(f.total_amount) as revenue
from dim_product p
join fact_sales f
on p.product_id = f.product_id
group by p.category
order by revenue desc;

-- phase 17 : customer purchase trend
select c.customer_name,
       d.month,
       count(f.sale_id) as purchases,
       sum(f.total_amount) as revenue
from dim_customer c
join fact_sales f
on c.customer_id = f.customer_id
join dim_date d
on f.date_id = d.date_id
group by c.customer_name, d.month
order by c.customer_name;

-- phase 18 : product performance
select p.product_name,
       sum(f.quantity) as quantity_sold,
       sum(f.total_amount) as revenue
from dim_product p
join fact_sales f
on p.product_id = f.product_id
group by p.product_name
order by revenue desc;

-- phase 19 : branch performance
select b.branch_name,
       b.region,
       sum(f.quantity) as quantity_sold,
       sum(f.total_amount) as revenue
from dim_branch b
join fact_sales f
on b.branch_id = f.branch_id
group by b.branch_name, b.region
order by revenue desc;

-- phase 20 : regional sales
select b.region,
       sum(f.total_amount) as revenue
from dim_branch b
join fact_sales f
on b.branch_id = f.branch_id
group by b.region
order by revenue desc;

-- phase 21 : sales trend
select d.date,sum(f.total_amount) as revenue
from dim_date d
join fact_sales f
on d.date_id = f.date_id
group by d.date
order by d.date;

-- phase 22 : display star schema tables
select * from dim_customer;
select * from dim_product;
select * from dim_branch;
select * from dim_date;
select * from fact_sales;