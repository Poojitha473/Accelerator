-- task 1: create database and schema
create or replace database customer_scd_db;

use database customer_scd_db;

create or replace schema retail_schema;

use schema retail_schema;

-- task 2: create scd type 1 table
create or replace table dim_customer_type1 (
    customer_key number autoincrement,
    customer_id number,
    customer_name varchar(100),
    city varchar(50),
    state varchar(50),
    membership varchar(30),
    segment varchar(30)
);

-- task 3: create stage for csv files
create or replace stage customer_stage;

-- upload these two files to customer_stage:
-- 1. customers_initial.csv
-- 2. customer_updates.csv
--
-- the files are given in the project question.
-- upload them through:
-- stage -> customer_stage -> upload files

-- task 3: load initial data into type 1 table
copy into dim_customer_type1
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
select count(*) as total_records
from dim_customer_type1;

-- display initial data
select
    customer_id,
    customer_name,
    city,
    state,
    membership,
    segment
from dim_customer_type1
order by customer_id;

-- create staging table for update file
create or replace table customer_updates (
    customer_id number,
    customer_name varchar(100),
    city varchar(50),
    state varchar(50),
    membership varchar(30),
    segment varchar(30),
    effective_date date
);

-- load customer updates
copy into customer_updates
(
    customer_id,
    customer_name,
    city,
    state,
    membership,
    segment,
    effective_date
)
from (
    select
        $1::number,
        $2::varchar,
        $3::varchar,
        $4::varchar,
        $5::varchar,
        $6::varchar,
        current_date()
    from @customer_stage
)
files = ('customer_updates.csv')
file_format = (
    type = csv,
    skip_header = 1,
    field_optionally_enclosed_by = '"'
);

-- check update records
select count(*) as update_records
from customer_updates;

-- task 4: apply scd type 1 updates
-- type 1 overwrites the existing customer information.
-- no new row is created.
update dim_customer_type1 d
set
    city = u.city,
    state = u.state,
    membership = u.membership,
    segment = u.segment
from customer_updates u
where d.customer_id = u.customer_id;

-- task 5: display type 1 result
select
    customer_id,
    customer_name,
    city,
    state,
    membership,
    segment
from dim_customer_type1
order by customer_id;

-- task 6: demonstrate type 1 history loss
-- customer 101 now contains only the new information.
select
    customer_id,
    city,
    state,
    membership
from dim_customer_type1
where customer_id = 101;

-- task 7 and 8: create scd type 2 table
create or replace table dim_customer_type2 (
    customer_key number autoincrement,
    customer_id number,
    customer_name varchar(100),
    city varchar(50),
    state varchar(50),
    membership varchar(30),
    segment varchar(30),
    effective_date date,
    expiry_date date,
    is_current boolean
);

-- task 9: load initial type 2 records
-- initial records start from 2026-01-01.
-- 9999-12-31 represents an open/current record.
insert into dim_customer_type2
(
    customer_id,
    customer_name,
    city,
    state,
    membership,
    segment,
    effective_date,
    expiry_date,
    is_current
)
select
    customer_id,
    customer_name,
    city,
    state,
    membership,
    segment,
    '2026-01-01'::date,
    '9999-12-31'::date,
    true
from dim_customer_type1
where customer_id not in (
    select customer_id
    from customer_updates
);

-- insert all original customers separately.
-- this is required because type 1 table has already been updated.
insert into dim_customer_type2
(
    customer_id,
    customer_name,
    city,
    state,
    membership,
    segment,
    effective_date,
    expiry_date,
    is_current
)
select
    101, 'Amit Sharma', 'Hyderabad', 'Telangana',
    'Silver', 'Regular',
    '2026-01-01'::date,
    '9999-12-31'::date,
    true

union all

select
    103, 'Rahul Verma', 'Vijayawada', 'Andhra Pradesh',
    'Silver', 'Regular',
    '2026-01-01'::date,
    '9999-12-31'::date,
    true

union all

select
    104, 'Neha Patel', 'Hyderabad', 'Telangana',
    'Gold', 'Premium',
    '2026-01-01'::date,
    '9999-12-31'::date,
    true;

-- check initial type 2 records
select count(*) as total_records
from dim_customer_type2;

-- task 10: apply type 2 changes
-- step 1:
-- close the old record by setting expiry_date
-- and is_current = false.
update dim_customer_type2 d
set
    expiry_date = dateadd(day, -1, u.effective_date),
    is_current = false
from customer_updates u
where d.customer_id = u.customer_id
  and d.is_current = true;

-- step 2:
-- insert a new record containing the changed information.
insert into dim_customer_type2
(
    customer_id,
    customer_name,
    city,
    state,
    membership,
    segment,
    effective_date,
    expiry_date,
    is_current
)
select
    customer_id,
    customer_name,
    city,
    state,
    membership,
    segment,
    effective_date,
    '9999-12-31'::date,
    true
from customer_updates;

-- task 11: check customer 101 history
select
    customer_id,
    city,
    membership,
    effective_date,
    expiry_date,
    is_current
from dim_customer_type2
where customer_id = 101
order by effective_date;

-- task 12: check customer 103 history
select
    customer_id,
    city,
    membership,
    effective_date,
    expiry_date,
    is_current
from dim_customer_type2
where customer_id = 103
order by effective_date;

-- task 13: check customer 104 history
select
    customer_id,
    city,
    membership,
    effective_date,
    expiry_date,
    is_current
from dim_customer_type2
where customer_id = 104
order by effective_date;

-- task 14: display complete type 2 history
select
    customer_id,
    customer_name,
    city,
    state,
    membership,
    effective_date,
    expiry_date,
    is_current
from dim_customer_type2
order by customer_id, effective_date;

-- task 15: display only current customer records
select
    customer_id,
    customer_name,
    city,
    state,
    membership,
    segment
from dim_customer_type2
where is_current = true
order by customer_id;

-- task 16: historical customer analysis
-- find customer 101's membership on march 15, 2026.
select
    customer_id,
    customer_name,
    membership,
    city,
    effective_date,
    expiry_date
from dim_customer_type2
where customer_id = 101
  and '2026-03-15'::date between effective_date and expiry_date;

-- task 17: compare type 1 and type 2
select
    'scd type 1' as scd_type,
    'old value overwritten' as old_value,
    'not preserved' as history,
    'no' as new_row

union all

select
    'scd type 2',
    'old value preserved',
    'preserved',
    'yes';

-- task 18: final validation
-- type 1 should have 5 records.
select count(*) as scd_type1_record_count
from dim_customer_type1;

-- type 2 should have 8 records:
-- 5 original records + 3 new versions.
select count(*) as scd_type2_record_count
from dim_customer_type2;

-- current type 2 records should be 5.
select count(*) as scd_type2_current_record_count
from dim_customer_type2
where is_current = true;

-- historical type 2 records should be 3.
select count(*) as scd_type2_historical_record_count
from dim_customer_type2
where is_current = false;