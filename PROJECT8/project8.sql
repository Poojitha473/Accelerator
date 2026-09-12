-- task 1: create database and schema
create or replace database customer_scd_db;

use database customer_scd_db;

create or replace schema retail_schema;

use schema retail_schema;

-- task 2: create customer dimension
create or replace table dim_customer (
    customer_key number autoincrement,
    customer_id number,
    customer_name varchar(100),
    city varchar(100),
    state varchar(100),
    membership varchar(50),
    segment varchar(50)
);

-- task 3: create stage
create or replace stage customer_stage;

-- task 4: load initial customer data
copy into dim_customer
(
    customer_id,
    customer_name,
    city,
    state,
    membership,
    segment
)
from @customer_stage
files = ('customers_initial.csv')
file_format = (
    type = csv,
    skip_header = 1,
    field_optionally_enclosed_by = '"'
);

-- check initial records
select count(*) as total_customers
from dim_customer;

-- display initial data
select
    customer_id,
    customer_name,
    city,
    state,
    membership,
    segment
from dim_customer
order by customer_id;

-- task 5: create update table
create or replace table customer_updates (
    customer_id number,
    customer_name varchar(100),
    city varchar(100),
    state varchar(100),
    membership varchar(50),
    segment varchar(50)
);

-- load update csv file
copy into customer_updates
from @customer_stage
files = ('customer_updates.csv')
file_format = (
    type = csv,
    skip_header = 1,
    field_optionally_enclosed_by = '"'
);

-- check update records
select count(*) as records_received
from customer_updates;

-- task 6: find changed customers
select
    d.customer_id,
    d.city as old_city,
    u.city as new_city,
    d.membership as old_membership,
    u.membership as new_membership
from dim_customer d
join customer_updates u
    on d.customer_id = u.customer_id
where d.city <> u.city
   or d.state <> u.state
   or d.membership <> u.membership
   or d.segment <> u.segment
order by d.customer_id;

-- task 7: find attribute changes
select
    d.customer_id,
    'city' as attribute,
    d.city as old_value,
    u.city as new_value
from dim_customer d
join customer_updates u
    on d.customer_id = u.customer_id
where d.city <> u.city

union all

select
    d.customer_id,
    'state' as attribute,
    d.state as old_value,
    u.state as new_value
from dim_customer d
join customer_updates u
    on d.customer_id = u.customer_id
where d.state <> u.state

union all

select
    d.customer_id,
    'membership' as attribute,
    d.membership as old_value,
    u.membership as new_value
from dim_customer d
join customer_updates u
    on d.customer_id = u.customer_id
where d.membership <> u.membership

union all

select
    d.customer_id,
    'segment' as attribute,
    d.segment as old_value,
    u.segment as new_value
from dim_customer d
join customer_updates u
    on d.customer_id = u.customer_id
where d.segment <> u.segment

order by customer_id, attribute;

-- task 8: overwrite old customer information
update dim_customer d
set
    city = u.city,
    state = u.state,
    membership = u.membership,
    segment = u.segment
from customer_updates u
where d.customer_id = u.customer_id;

-- task 9: display updated dimension
select
    customer_id,
    customer_name,
    city,
    state,
    membership,
    segment
from dim_customer
order by customer_id;

-- task 10: check customer 101
select
    customer_id,
    customer_name,
    city,
    state,
    membership
from dim_customer
where customer_id = 101;

-- task 11: business impact
select
    customer_id,
    city as current_city,
    state as current_state,
    membership as current_membership
from dim_customer
where customer_id in (101, 103, 104)
order by customer_id;