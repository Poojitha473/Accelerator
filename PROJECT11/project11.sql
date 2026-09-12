-- task 1: create database and schema
-- create database
create database if not exists customer_mdm_db;

-- use database
use database customer_mdm_db;

-- create schema
create schema if not exists customer_schema;

-- use schema
use schema customer_schema;

-- create file format for csv files
create or replace file format customer_csv_format
type = 'csv'
field_delimiter = ','
skip_header = 1
field_optionally_enclosed_by = '"';

-- create stage to store customer csv files
create or replace stage customer_stage
file_format = customer_csv_format;

-- check stage
list @customer_stage;

-- task 2: create source tables
-- create table for initial customer csv
create or replace table customer_initial(
customer_id number,customer_name varchar,city varchar,
state varchar,membership varchar,segment varchar
);

-- create table for customer update csv
create or replace table customer_updates(
customer_id number,customer_name varchar,city varchar,
state varchar,membership varchar,segment varchar,effective_date date
);

-- task 3: load csv files into source tables
-- load customers_initial.csv
copy into customer_initial
from @customer_stage/customers_initial.csv
file_format = customer_csv_format;

-- load customer_updates.csv
copy into customer_updates
from @customer_stage/customer_updates.csv
file_format = customer_csv_format;

-- verify source data
-- display initial customer data
select * from customer_initial
order by customer_id;

-- display update customer data
select * from customer_updates
order by customer_id;

-- task 4: create hybrid dimension table
-- create hybrid customer dimension
create or replace table dim_customer_hybrid(
customer_key number autoincrement,customer_id number,
customer_name varchar,city varchar,
previous_city varchar,state varchar,current_membership varchar,
previous_membership varchar,historical_membership varchar,segment varchar,
effective_date date,expiry_date date,is_current boolean
);

-- task 5: load initial dimension data
-- load initial customers from source table
insert into dim_customer_hybrid(
customer_id,customer_name,city,previous_city,
state,current_membership,previous_membership,historical_membership,segment,
effective_date,expiry_date,is_current
)
select customer_id,customer_name,city,null,
state,membership,null,membership,
segment,'2026-01-01','9999-12-31',true
from customer_initial;

-- check initial record count
select count(*) as total_records
from dim_customer_hybrid;

-- check current record count
select count(*) as current_records
from dim_customer_hybrid
where is_current = true;

-- task 6: display initial dimension state
-- display initial dimension records
select customer_id,customer_name,city,previous_city,
state,current_membership,previous_membership,historical_membership,segment,
effective_date,expiry_date,is_current
from dim_customer_hybrid
order by customer_id;

-- task 7: expire old records
-- expire customer 101 old record
update dim_customer_hybrid
set expiry_date = '2026-03-31',is_current = false
where customer_id = 101 and is_current = true;

-- expire customer 103 old record
update dim_customer_hybrid
set expiry_date = '2026-04-04',is_current = false
where customer_id = 103 and is_current = true;

-- expire customer 104 old record
update dim_customer_hybrid
set expiry_date = '2026-04-09',is_current = false
where customer_id = 104 and is_current = true;

-- insert new customer versions
insert into dim_customer_hybrid(
customer_id,customer_name,city,previous_city,
state,current_membership,previous_membership,historical_membership,segment,
effective_date,expiry_date,is_current
)
select u.customer_id,u.customer_name,u.city,
i.city,u.state,u.membership,i.membership,
u.membership,u.segment,
u.effective_date,'9999-12-31',true
from customer_updates u
join customer_initial i
on u.customer_id = i.customer_id;

-- task 8: synchronize hybrid attributes
-- update all versions of customer 101
update dim_customer_hybrid
set city = 'Bengaluru',state = 'Karnataka',
current_membership = 'Gold',previous_membership = 'Silver',
previous_city = 'Hyderabad'
where customer_id = 101;

-- update all versions of customer 103
update dim_customer_hybrid
set city = 'Chennai',state = 'Tamil Nadu',
current_membership = 'Gold',previous_membership = 'Silver',
previous_city = 'Vijayawada'
where customer_id = 103;

-- update all versions of customer 104
update dim_customer_hybrid
set city = 'Hyderabad',state = 'Telangana',
current_membership = 'Platinum',previous_membership = 'Gold'
where customer_id = 104;

-- task 9: display complete dimension history
-- display all historical and current records
select customer_id,customer_name,city,previous_city,
state,current_membership,previous_membership,historical_membership,segment,
effective_date,expiry_date,is_current
from dim_customer_hybrid
order by customer_id, effective_date;

-- task 10: display active customer report
-- display only current customer records
select customer_id,customer_name,city,previous_city,
state,current_membership,previous_membership,segment
from dim_customer_hybrid
where is_current = true
order by customer_id;

-- task 11: point-in-time historical query
-- find customer 101 information on march 15, 2026
select customer_id,customer_name,city,historical_membership,segment,
effective_date,expiry_date
from dim_customer_hybrid
where customer_id = 101
and '2026-03-15' between effective_date and expiry_date;

-- task 12: metric validation
-- total record count
select count(*) as total_record_count
from dim_customer_hybrid;

-- current record count
select count(*) as current_record_count
from dim_customer_hybrid
where is_current = true;

-- historical record count
select count(*) as historical_record_count
from dim_customer_hybrid
where is_current = false;

-- display all metrics together
select count(*) as total_record_count,
count_if(is_current = true) as current_record_count,
count_if(is_current = false) as historical_record_count
from dim_customer_hybrid;