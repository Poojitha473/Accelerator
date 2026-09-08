-- phase 1 : snowflake environment
-- create warehouse
create warehouse if not exists enterprise_wh
warehouse_size = 'x-small'
auto_suspend = 60
auto_resume = true;

-- create database and schema
create database if not exists enterprise_db;
create schema if not exists enterprise_db.sales_schema;

-- use warehouse, database and schema
use warehouse enterprise_wh;
use database enterprise_db;
use schema sales_schema;

-- create csv file format
create or replace file format csv_format
type = csv
skip_header = 1
field_optionally_enclosed_by = '"';

-- create internal stage
create or replace stage sales_stage
file_format = csv_format;

-- phase 2 : create tables and load data
-- create customers table
create or replace table customers (
    customer_id number,
    customer_name varchar,
    city varchar,
    membership varchar
);

-- create products table
create or replace table products (
    product_id number,
    product_name varchar,
    category varchar,
    price number(12,2)
);

-- create branches table
create or replace table branches (
    branch_id number,
    branch_name varchar,
    state varchar
);

-- create sales table
create or replace table sales (
    sale_id number,
    customer_id number,
    product_id number,
    branch_id number,
    quantity number,
    sale_date date,
    total_amount number(12,2)
);

-- create incremental staging table
create or replace table sales_incremental like sales;

-- upload csv files into @sales_stage using snowsight
-- load customers
copy into customers
from @sales_stage/customers.csv
file_format = csv_format;

-- load products
copy into products
from @sales_stage/products.csv
file_format = csv_format;

-- load branches
copy into branches
from @sales_stage/branches.csv
file_format = csv_format;

-- load historical sales
copy into sales
from @sales_stage/sales_history.csv
file_format = csv_format;

LIST @sales_stage;
-- verify sales
select * from sales;

-- phase 3 : incremental loading
-- create stream on incremental table
create or replace stream sales_stream
on table sales_incremental;

-- load new sales
copy into sales_incremental
from @sales_stage/new_sales.csv
file_format = csv_format;

-- display newly inserted records
select
    sale_id,
    customer_id,
    product_id,
    branch_id,
    quantity,
    sale_date,
    total_amount,
    metadata$action
from sales_stream
where metadata$action = 'INSERT';

-- merge new records into sales
merge into sales t
using sales_stream s
on t.sale_id = s.sale_id

when not matched then
insert values (
    s.sale_id,
    s.customer_id,
    s.product_id,
    s.branch_id,
    s.quantity,
    s.sale_date,
    s.total_amount
);

-- verify incremental load
select * from sales order by sale_id;

-- phase 4 : data validation
-- find duplicate sale ids
select sale_id, count(*)
from sales
group by sale_id
having count(*) > 1;

-- find missing customer ids
select s.*
from sales s
left join customers c
on s.customer_id = c.customer_id
where c.customer_id is null;

-- find invalid product ids
select s.*
from sales s
left join products p
on s.product_id = p.product_id
where p.product_id is null;

-- count newly loaded records
select count(*) as new_records
from sales_incremental;

-- phase 5 : time travel
-- delete one record
delete from sales
where sale_id = 10;

-- view deleted record using time travel
select *
from sales at(offset => -60)
where sale_id = 10;

-- recover deleted record
insert into sales
select *
from sales at(offset => -60)
where sale_id = 10;

-- verify recovery
select *
from sales
where sale_id = 10;

-- phase 6 : zero copy clone
-- create clone
create or replace table sales_test
clone sales;

-- display clone
select * from sales_test;

-- insert record into clone
insert into sales_test
values (999,1,101,1,1,'2026-08-19',60000);

-- check original table
select *
from sales
where sale_id = 999;

-- phase 7 : task automation
-- create daily task
create or replace task daily_sales_task
warehouse = enterprise_wh
schedule = 'USING CRON 0 1 * * * UTC'
when system$stream_has_data('sales_stream')
as
merge into sales t
using sales_stream s
on t.sale_id = s.sale_id
when not matched then
insert values (
    s.sale_id,
    s.customer_id,
    s.product_id,
    s.branch_id,
    s.quantity,
    s.sale_date,
    s.total_amount
);

-- resume task
alter task daily_sales_task resume;

-- verify task
show tasks;

-- phase 8 : business analytics
-- 28. customer revenue
select c.customer_name,
       sum(s.total_amount) as revenue
from customers c
join sales s
on c.customer_id = s.customer_id
group by c.customer_name
order by revenue desc;

-- 29. branch revenue
select b.branch_name,
       sum(s.total_amount) as revenue
from branches b
join sales s
on b.branch_id = s.branch_id
group by b.branch_name
order by revenue desc;

-- 30. product revenue
select p.product_name,
       sum(s.total_amount) as revenue
from products p
join sales s
on p.product_id = s.product_id
group by p.product_name
order by revenue desc;

-- 31. monthly revenue
select date_trunc('month', sale_date) as month,
       sum(total_amount) as revenue
from sales
group by 1
order by 1;

-- 32. highest revenue customer
select c.customer_name,
       sum(s.total_amount) as revenue
from customers c
join sales s
on c.customer_id = s.customer_id
group by c.customer_name
order by revenue desc
limit 1;

-- 33. highest revenue branch
select b.branch_name,
       sum(s.total_amount) as revenue
from branches b
join sales s
on b.branch_id = s.branch_id
group by b.branch_name
order by revenue desc
limit 1;

-- 34. top five products
select p.product_name,
       sum(s.total_amount) as revenue
from products p
join sales s
on p.product_id = s.product_id
group by p.product_name
order by revenue desc
limit 5;

-- 35. customer purchase frequency
select c.customer_name,
       count(s.sale_id) as purchases
from customers c
join sales s
on c.customer_id = s.customer_id
group by c.customer_name
order by purchases desc;

-- 36. running revenue
select sale_date,
       sale_id,
       total_amount,
       sum(total_amount) over(
           order by sale_date, sale_id
       ) as running_revenue
from sales;

-- 37. customer ranking
select c.customer_name,
       sum(s.total_amount) as revenue,
       rank() over(
           order by sum(s.total_amount) desc
       ) as ranking
from customers c
join sales s
on c.customer_id = s.customer_id
group by c.customer_name
order by ranking;

-- phase 9 : views
-- 38. customer revenue view
create or replace view customer_revenue as
select c.customer_id,
       c.customer_name,
       sum(s.total_amount) as revenue
from customers c
join sales s
on c.customer_id = s.customer_id
group by c.customer_id, c.customer_name;

-- display customer revenue
select * from customer_revenue;

-- 39. branch revenue view
-- use view because some snowflake accounts do not support
-- materialized views
create or replace view branch_revenue as
select b.branch_id,b.branch_name,sum(s.total_amount) as revenue
from branches b join sales s
on b.branch_id = s.branch_id
group by b.branch_id, b.branch_name;

-- display branch revenue
select * from branch_revenue;