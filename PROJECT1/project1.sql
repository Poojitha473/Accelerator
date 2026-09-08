-- create warehouse
create warehouse SALES_WH
with
warehouse_size='x-small'
auto_suspend=60
auto_resume=True;

-- check that warehouse has been created 
show warehouses;

-- create database
create database CUSTOMER_SALES_DB;

-- check that database has been created
show databases;

-- create schema
create schema CUSTOMER_SALES_DB.SALES_SCHEMA;

-- check that schema has been created
show schemas in database CUSTOMER_SALES_DB;

-- select the warehouse,database and schema
use warehouse SALES_WH;
use database CUSTOMER_SALES_DB;
use schema SALES_SCHEMA;


-- create csv file format
create or replace file format csv_format type='csv'
field_delimiter=','
skip_header=1
record_delimiter = '\n';

-- create internal stage
create stage sales_stage
file_format=csv_format;

-- create customers table
create table customers(
    customer_id integer,
    first_name varchar,
    last_name varchar,
    email varchar,
    phone varchar,
    address varchar
);

-- create fooditems table
create table fooditems(
    food_id integer,
    name varchar,
    price number(10,2),
    category varchar,
    availability varchar
);

-- create orders table
create table orders(
    order_id integer,
    customer_id integer,
    food_id integer,
    quantity integer,
    order_date timestamp,
    status varchar,
    total_amount number(10,2)
);

-- load customers data
copy into customers
from @sales_stage/customers.csv
file_format=csv_format;

-- load fooditems data
copy into fooditems
from @sales_stage/fooditems.csv
file_format = csv_format;

-- load orders data
copy into orders
from @sales_stage/orders.csv
file_format = csv_format;

-- verify customers data
select * from customers;

-- verify fooditems data
select * from fooditems;

-- verify orders data
select * from orders;

-- customer-wise sales report
select c.customer_id,concat(c.first_name, ' ', c.last_name) as customer_name,
sum(o.total_amount) as total_amount_spent
from customers c inner join orders o
on c.customer_id=o.customer_id
group by c.customer_id,c.first_name,c.last_name
order by total_amount_spent desc;

-- highest spending customer
select c.customer_id,concat(c.first_name, ' ', c.last_name) as customer_name,
sum(o.total_amount) as total_spent
from customers c inner join orders o
on c.customer_id=o.customer_id
group by c.customer_id,c.first_name,c.last_name
order by total_spent desc
limit 1;

-- total business revenue
select sum(total_amount) as total_revenue
from orders;

-- category-wise revenue
select f.category,sum(o.total_amount) as revenue
from orders o inner join fooditems f
on o.food_id=f.food_id
group by f.category
order by revenue desc;

-- order status-wise revenue
select status,sum(total_amount) as revenue
from orders
group by status
order by revenue desc;

-- top 3 customers
select c.customer_id,concat(c.first_name, ' ', c.last_name) as customer_name,
sum(o.total_amount) as total_spent
from customers c inner join orders o
on c.customer_id = o.customer_id
group by c.customer_id,c.first_name,c.last_name
order by total_spent desc
limit 3;

-- customer purchase frequency
select c.customer_id,concat(c.first_name, ' ', c.last_name) as customer_name,
count(o.order_id) as orders_placed
from customers c inner join orders o
on c.customer_id=o.customer_id
group by c.customer_id,c.first_name,c.last_name
order by orders_placed desc;

-- display delivered orders
select * from orders
where status='Delivered';

-- orders after july 12
select o.order_id,concat(c.first_name, ' ', c.last_name) as customer_name,
o.order_date,o.status,o.total_amount
from orders o inner join customers c
on o.customer_id = c.customer_id
where o.order_date > '2026-07-12'
order by o.order_date;

-- create customer sales view
create view customer_sales_report as
select c.customer_id,concat(c.first_name, ' ', c.last_name) as customer_name,
sum(o.total_amount) as total_amount_spent
from customers c inner join orders o
on c.customer_id = o.customer_id
group by c.customer_id,c.first_name,c.last_name;

-- display customer sales view
select * from customer_sales_report;

-- sort customer sales view
select * from customer_sales_report
order by total_amount_spent desc;

