-- task 1: create database and schema
create or replace database customer_history_db;

use database customer_history_db;

create or replace schema retail_schema;

use schema retail_schema;

-- create stage for csv files
create or replace stage customer_stage;

-- upload these two files to customer_stage:
-- 1. customers_initial.csv
-- 2. customer_updates.csv
--
-- upload them from:
-- database -> schema -> stages -> customer_stage -> upload files
-- create staging table for initial csv
create or replace table customer_initial (
    customer_id number,
    customer_name varchar(100),
    city varchar(50),
    state varchar(50),
    membership varchar(30),
    segment varchar(30)
);

-- load customers_initial.csv
copy into customer_initial
from @customer_stage
files = ('customers_initial.csv')
file_format = (
    type = csv,
    skip_header = 1,
    field_optionally_enclosed_by = '"'
);

-- create staging table for update csv
create or replace table customer_updates (
    customer_id number,
    customer_name varchar(100),
    city varchar(50),
    state varchar(50),
    membership varchar(30),
    segment varchar(30),
    effective_date date
);

-- load customer_updates.csv
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

-- task 2: create scd type 3 dimension
create or replace table dim_customer_type3 (
    customer_key number autoincrement,
    customer_id number,
    customer_name varchar(100),
    city varchar(50),
    state varchar(50),
    current_membership varchar(30),
    previous_membership varchar(30),
    segment varchar(30)
);

-- task 3: load initial type 3 data
-- for the initial load:
-- current_membership = membership
-- previous_membership = null
insert into dim_customer_type3
(
    customer_id,
    customer_name,
    city,
    state,
    current_membership,
    previous_membership,
    segment
)
select
    customer_id,
    customer_name,
    city,
    state,
    membership,
    null,
    segment
from customer_initial;

-- check total customers
select count(*) as total_customers
from dim_customer_type3;

-- task 4: display initial type 3 data
select
    customer_id,
    customer_name,
    city,
    current_membership,
    previous_membership
from dim_customer_type3
order by customer_id;

-- task 5 and 6: apply scd type 3 changes

update dim_customer_type3 d
set
    previous_membership = d.current_membership,
    current_membership = u.membership,
    city = u.city,
    state = u.state,
    segment = u.segment
from customer_updates u
where d.customer_id = u.customer_id
  and d.current_membership <> u.membership;

-- task 7: display final type 3 report
select
    customer_id,
    customer_name,
    city,
    current_membership,
    previous_membership
from dim_customer_type3
order by customer_id;

-- task 8: demonstrate type 3
-- customer 101 should show:
-- current membership  = gold
-- previous membership = silver
select
    customer_id,
    customer_name,
    current_membership,
    previous_membership
from dim_customer_type3
where customer_id = 101;

-- task 9: create scd type 6 dimension
create or replace table dim_customer_type6 (
    customer_key number autoincrement,
    customer_id number,
    customer_name varchar(100),
    city varchar(50),
    state varchar(50),
    current_membership varchar(30),
    previous_membership varchar(30),
    historical_membership varchar(30),
    segment varchar(30),
    effective_date date,
    expiry_date date,
    is_current boolean
);

-- task 10: load initial type 6 records
insert into dim_customer_type6
(
    customer_id,
    customer_name,
    city,
    state,
    current_membership,
    previous_membership,
    historical_membership,
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
    null,
    membership,
    segment,
    '2026-01-01'::date,
    '9999-12-31'::date,
    true
from customer_initial;

-- check initial type 6 records

select count(*) as total_records
from dim_customer_type6;

select count(*) as current_records
from dim_customer_type6
where is_current = true;

-- task 11: apply type 6 change for customer 101
-- step 1:
update dim_customer_type6 d
set
    expiry_date = dateadd(day, -1, u.effective_date),
    is_current = false
from customer_updates u
where d.customer_id = u.customer_id
  and d.is_current = true
  and u.customer_id = 101;

-- step 2:
-- insert the new version.
insert into dim_customer_type6
(
    customer_id,
    customer_name,
    city,
    state,
    current_membership,
    previous_membership,
    historical_membership,
    segment,
    effective_date,
    expiry_date,
    is_current
)
select
    u.customer_id,
    u.customer_name,
    u.city,
    u.state,
    u.membership,
    d.current_membership,
    u.membership,
    u.segment,
    u.effective_date,
    '9999-12-31'::date,
    true
from customer_updates u
join dim_customer_type6 d
    on u.customer_id = d.customer_id
where u.customer_id = 101
  and d.is_current = false
  and d.expiry_date = dateadd(day, -1, u.effective_date);

-- task 12: apply remaining type 6 changes
-- expire the old records for customers 103 and 104.
update dim_customer_type6 d
set
    expiry_date = dateadd(day, -1, u.effective_date),
    is_current = false
from customer_updates u
where d.customer_id = u.customer_id
  and d.is_current = true
  and u.customer_id in (103, 104);

-- insert new versions for customers 103 and 104.
insert into dim_customer_type6
(
    customer_id,
    customer_name,
    city,
    state,
    current_membership,
    previous_membership,
    historical_membership,
    segment,
    effective_date,
    expiry_date,
    is_current
)
select
    u.customer_id,
    u.customer_name,
    u.city,
    u.state,
    u.membership,
    d.current_membership,
    u.membership,
    u.segment,
    u.effective_date,
    '9999-12-31'::date,
    true
from customer_updates u
join dim_customer_type6 d
    on u.customer_id = d.customer_id
where u.customer_id in (103, 104)
  and d.is_current = false
  and d.expiry_date = dateadd(day, -1, u.effective_date);

-- task 13: display complete type 6 history
select
    customer_id,
    customer_name,
    current_membership,
    previous_membership,
    effective_date,
    expiry_date,
    is_current
from dim_customer_type6
order by customer_id, effective_date;

-- task 14: current customer report
select
    customer_id,
    customer_name,
    city,
    current_membership,
    previous_membership
from dim_customer_type6
where is_current = true
order by customer_id;

-- task 15: point-in-time historical query
select
    customer_id,
    customer_name,
    current_membership,
    effective_date,
    expiry_date
from dim_customer_type6
where customer_id = 101
  and '2026-03-15'::date between effective_date and expiry_date;

-- task 16: compare type 3 and type 6
select
    'scd type 3' as scd_type,
    'yes' as current_value,
    'yes' as previous_value,
    'no' as historical_rows,
    'no' as effective_date,
    'no' as expiry_date,
    'no' as is_current

union all
select
    'scd type 6',
    'yes',
    'yes',
    'yes',
    'yes',
    'yes',
    'yes';

-- task 17: record count validation
select count(*) as scd_type3_record_count
from dim_customer_type3;

-- type 6:
select count(*) as scd_type6_record_count
from dim_customer_type6;

-- current type 6 records = 5
select count(*) as scd_type6_current_record_count
from dim_customer_type6
where is_current = true;

-- historical type 6 records = 3
select count(*) as scd_type6_historical_record_count
from dim_customer_type6
where is_current = false;