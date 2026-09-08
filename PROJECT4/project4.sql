-- phase 1 : snowflake environment
-- create warehouse
create warehouse if not exists retail_wh
warehouse_size = 'x-small'
auto_suspend = 60
auto_resume = true;

-- create database and schema
create database if not exists retail_dw;
create schema if not exists retail_dw.sales_schema;

-- use objects
use warehouse retail_wh;
use database retail_dw;
use schema sales_schema;

-- phase 2 : file format and stage
-- create csv format
create or replace file format csv_format
type = csv
skip_header = 1
field_optionally_enclosed_by = '"';

-- create stage
create or replace stage retail_stage
file_format = csv_format;

-- phase 3 : dimension tables
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

-- phase 4 : fact table
-- fact table stores sales transactions
create or replace table fact_sales (
    sale_id number primary key,
    customer_id number,
    product_id number,
    branch_id number,
    date_id number,
    quantity number,
    total_amount number(12,2)
);

-- phase 5 : load dimension data
-- upload these files into @retail_stage using snowsight
-- customers.csv
-- products.csv
-- branches.csv
-- calendar.csv
-- sales.csv

-- load customer data
copy into dim_customer
from @retail_stage/customers.csv
file_format = csv_format;

-- load product data
copy into dim_product
from @retail_stage/products.csv
file_format = csv_format;

-- load branch data
copy into dim_branch
from @retail_stage/branches.csv
file_format = csv_format;

-- load date data
copy into dim_date
from @retail_stage/calendar.csv
file_format = csv_format;

-- load sales data
copy into fact_sales
from @retail_stage/sales.csv
file_format = csv_format;

-- phase 6 : validation
-- check customer records
select * from dim_customer;

-- check product records
select * from dim_product;

-- check branch records
select * from dim_branch;

-- check date records
select * from dim_date;

-- check fact records
select * from fact_sales;

-- phase 7 : dimensional model relationships
-- customer to fact
select c.customer_name,
       f.sale_id,
       f.quantity,
       f.total_amount
from dim_customer c
join fact_sales f
on c.customer_id = f.customer_id;

-- product to fact
select p.product_name,
       f.quantity,
       f.total_amount
from dim_product p
join fact_sales f
on p.product_id = f.product_id;

-- branch to fact
select b.branch_name,
       f.total_amount
from dim_branch b
join fact_sales f
on b.branch_id = f.branch_id;

-- date to fact
select d.date,
       d.month,
       d.quarter,
       d.year,
       f.total_amount
from dim_date d
join fact_sales f
on d.date_id = f.date_id;

-- phase 8 : business analytics
-- customer revenue report
select c.customer_name,
       sum(f.total_amount) as revenue
from dim_customer c
join fact_sales f
on c.customer_id = f.customer_id
group by c.customer_name
order by revenue desc;

-- product revenue report
select p.product_name,
       sum(f.total_amount) as revenue
from dim_product p
join fact_sales f
on p.product_id = f.product_id
group by p.product_name
order by revenue desc;

-- branch performance report
select b.branch_name,
       sum(f.total_amount) as revenue
from dim_branch b
join fact_sales f
on b.branch_id = f.branch_id
group by b.branch_name
order by revenue desc;

-- monthly revenue
select d.month,
       d.year,
       sum(f.total_amount) as revenue
from dim_date d
join fact_sales f
on d.date_id = f.date_id
group by d.month, d.year
order by d.year, d.month;

-- state-wise sales
select b.state,
       sum(f.total_amount) as revenue
from dim_branch b
join fact_sales f
on b.branch_id = f.branch_id
group by b.state
order by revenue desc;

-- category-wise revenue
select p.category,
       sum(f.total_amount) as revenue
from dim_product p
join fact_sales f
on p.product_id = f.product_id
group by p.category
order by revenue desc;

-- top 10 customers
select c.customer_name,
       sum(f.total_amount) as revenue
from dim_customer c
join fact_sales f
on c.customer_id = f.customer_id
group by c.customer_name
order by revenue desc
limit 10;

-- top 10 products
select p.product_name,
       sum(f.total_amount) as revenue
from dim_product p
join fact_sales f
on p.product_id = f.product_id
group by p.product_name
order by revenue desc
limit 10;

-- top 10 branches
select b.branch_name,
       sum(f.total_amount) as revenue
from dim_branch b
join fact_sales f
on b.branch_id = f.branch_id
group by b.branch_name
order by revenue desc
limit 10;

-- sales trend
select d.date,
       sum(f.total_amount) as revenue
from dim_date d
join fact_sales f
on d.date_id = f.date_id
group by d.date
order by d.date;

-- customer purchase analysis
select c.customer_name,
       count(f.sale_id) as purchases,
       sum(f.quantity) as quantity,
       sum(f.total_amount) as revenue
from dim_customer c
join fact_sales f
on c.customer_id = f.customer_id
group by c.customer_name
order by revenue desc;

-- quarterly revenue
select d.year,
       d.quarter,
       sum(f.total_amount) as revenue
from dim_date d
join fact_sales f
on d.date_id = f.date_id
group by d.year, d.quarter
order by d.year, d.quarter;