-- task 1: create database and schema
-- create database
create database if not exists retail_schemas_dw;

-- use database
use database retail_schemas_dw;

-- create schema
create schema if not exists schema_comparison;

-- use schema
use schema schema_comparison;

-- create file format for csv files
create or replace file format csv_format
    type = csv
    field_delimiter = ','
    skip_header = 1
    field_optionally_enclosed_by = '"'
    null_if = ('null', '');

-- create internal stage for uploading csv files
create or replace stage retail_stage
    file_format = csv_format;

-- task 2: create source tables
-- source table for regions and stores
create or replace table src_regions_stores (
store_id number,store_name varchar(100),city varchar(50),
state varchar(50),region_name varchar(50),regional_manager varchar(100)
);

-- source table for products
create or replace table src_product_hierarchy (
product_id number,product_name varchar(100),
subcategory_name varchar(50),category_name varchar(50),unit_price number(10,2)
);

-- source table for customers
create or replace table src_customers (
customer_id number,customer_name varchar(100),
city varchar(50),state varchar(50)
);

-- source table for sales transactions
create or replace table src_sales_transactions (
transaction_id varchar(50),transaction_date date,
customer_id number,store_id number,
product_id number,quantity number,unit_price number(10,2)
);

-- task 3: load regions and stores csv
-- load regions_and_stores.csv into source table
copy into src_regions_stores
from @retail_stage/regions_and_stores.csv
file_format = csv_format
on_error = 'continue';

-- check loaded data
select *
from src_regions_stores;

-- task 4: load product hierarchy csv
-- load product_hierarchy.csv into source table
copy into src_product_hierarchy
from @retail_stage/product_hierarchy.csv
file_format = csv_format
on_error = 'continue';

-- check loaded data
select * from src_product_hierarchy;

-- task 5: load customers csv
-- load customers.csv into source table
copy into src_customers
from @retail_stage/customers.csv
file_format = csv_format
on_error = 'continue';

-- check loaded data
select * from src_customers;

-- task 6: load sales transactions csv
-- load sales_transactions.csv into source table
copy into src_sales_transactions
from @retail_stage/sales_transactions.csv
file_format = csv_format
on_error = 'continue';

-- check loaded data
select * from src_sales_transactions;

-- task 7: create star schema store dimension
-- create denormalized store dimension
create or replace table star_dim_store (
store_key number autoincrement primary key,store_id number,
store_name varchar(100),city varchar(50),state varchar(50),
region_name varchar(50),regional_manager varchar(100)
);

-- load store dimension from source table
insert into star_dim_store(
store_id,store_name,city,
state,region_name,regional_manager
)
select store_id,store_name,city,
state,region_name,regional_manager
from src_regions_stores;

-- check star store dimension
select * from star_dim_store;

-- task 8: create star schema product dimension
-- create denormalized product dimension
create or replace table star_dim_product (
    product_key number autoincrement primary key,
    product_id number,
    product_name varchar(100),
    subcategory_name varchar(50),
    category_name varchar(50),
    unit_price number(10,2)
);

-- load product dimension from source table
insert into star_dim_product(
product_id,product_name,subcategory_name,
category_name,unit_price
)
select product_id,product_name,subcategory_name,
category_name,unit_price
from src_product_hierarchy;

-- check star product dimension
select * from star_dim_product;

-- task 9: create star schema fact table
-- create sales fact table
create or replace table star_fact_sales (
sales_key number autoincrement primary key,transaction_id varchar(50),
transaction_date date,customer_id number,store_key number,
product_key number,quantity number,
total_amount number(12,2)
);

-- task 10: load star schema fact table
-- load sales data
-- surrogate keys are obtained from dimension tables
insert into star_fact_sales(
transaction_id,transaction_date,customer_id,store_key,
product_key,quantity,total_amount
)
select s.transaction_id,s.transaction_date,s.customer_id,
ds.store_key,dp.product_key,s.quantity,
s.quantity * s.unit_price as total_amount
from src_sales_transactions s
join star_dim_store ds on s.store_id = ds.store_id
join star_dim_product dp
on s.product_id = dp.product_id;

-- check star fact table
select * from star_fact_sales;

-- task 11: create snowflake schema region table
-- create normalized region table
create or replace table snow_dim_region (
region_key number autoincrement primary key,region_name varchar(50),
regional_manager varchar(100)
);

-- load unique regions from source table
insert into snow_dim_region(
region_name,regional_manager
)
select distinct region_name,regional_manager
from src_regions_stores;

-- check region table
select * from snow_dim_region;

-- task 12: create snowflake schema store table
-- create normalized store table
create or replace table snow_dim_store (
store_key number autoincrement primary key,store_id number,
store_name varchar(100),city varchar(50),
state varchar(50),region_key number
);

-- load store data using region key
insert into snow_dim_store(
store_id,store_name,city,
state,region_key
)
select s.store_id,s.store_name,
s.city,s.state,
r.region_key
from src_regions_stores s
join snow_dim_region r
on s.region_name = r.region_name;

-- check snowflake store table
select * from snow_dim_store;

-- task 13: create snowflake category table
-- create category table
create or replace table snow_dim_category (
category_key number autoincrement primary key,
category_name varchar(50)
);

-- load unique categories
insert into snow_dim_category(
category_name
)
select distinct category_name
from src_product_hierarchy;

-- check category table
select * from snow_dim_category;

-- task 14: create snowflake subcategory table
-- create subcategory table
create or replace table snow_dim_subcategory (
subcategory_key number autoincrement primary key,
subcategory_name varchar(50),category_key number
);

-- load subcategories using category key
insert into snow_dim_subcategory(
subcategory_name,category_key
)
select distinct p.subcategory_name,c.category_key
from src_product_hierarchy p
join snow_dim_category c
on p.category_name = c.category_name;

-- check subcategory table
select * from snow_dim_subcategory;

-- task 15: create snowflake product table
-- create normalized product table
create or replace table snow_dim_product (
product_key number autoincrement primary key,product_id number,
product_name varchar(100),unit_price number(10,2),subcategory_key number
);

-- load products using subcategory key
insert into snow_dim_product(
product_id,product_name,
unit_price,subcategory_key
)
select p.product_id,p.product_name,
p.unit_price,sc.subcategory_key
from src_product_hierarchy p
join snow_dim_subcategory sc
on p.subcategory_name = sc.subcategory_name;

-- check snowflake product table
select * from snow_dim_product;

-- task 16: create snowflake fact table
-- create normalized sales fact table
create or replace table snow_fact_sales (
sales_key number autoincrement primary key,
transaction_id varchar(50),transaction_date date,
customer_id number,store_key number,
product_key number,quantity number,
total_amount number(12,2)
);

-- task 17: load snowflake fact table
-- load sales data using normalized dimension keys
insert into snow_fact_sales(
transaction_id,transaction_date,customer_id,
store_key,product_key,quantity,total_amount
)
select
s.transaction_id,s.transaction_date,
s.customer_id,st.store_key,
p.product_key,s.quantity,s.quantity * s.unit_price as total_amount
from src_sales_transactions s
join snow_dim_store st
on s.store_id = st.store_id
join snow_dim_product p
on s.product_id = p.product_id;

-- check snowflake fact table
select * from snow_fact_sales;

-- task 18: star schema analytics
-- calculate total revenue by region and category
select ds.region_name,dp.category_name,sum(fs.total_amount) as total_revenue
from star_fact_sales fs
join star_dim_store ds
on fs.store_key = ds.store_key
join star_dim_product dp
on fs.product_key = dp.product_key
group by ds.region_name,dp.category_name
order by ds.region_name,dp.category_name;

-- task 19: snowflake schema analytics
-- calculate revenue using multiple normalized tables
select r.region_name,c.category_name,sum(fs.total_amount) as total_revenue
from snow_fact_sales fs
join snow_dim_store s
on fs.store_key = s.store_key
join snow_dim_region r
on s.region_key = r.region_key
join snow_dim_product p
on fs.product_key = p.product_key
join snow_dim_subcategory sc
on p.subcategory_key = sc.subcategory_key
join snow_dim_category c
on sc.category_key = c.category_key
group by r.region_name,c.category_name
order by r.region_name,c.category_name;

-- task 20: star vs snowflake comparison
-- compare both schema architectures
select 'dimension normalization level' as metric_feature,
'denormalized (flat)' as star_schema,
'normalized (hierarchical)' as snowflake_schema
union all
select 'total dimension tables','2 tables','5 tables'
union all
select 'joins for category revenue','2 joins','5 joins'
union all
select 'data redundancy','higher','lower'
union all
select 'query simplicity','high','lower';

-- task 21: regional manager sales performance
-- calculate total quantity and sales amount by manager
select ds.regional_manager,
sum(fs.quantity) as total_items_sold,
sum(fs.total_amount) as total_sales_amount
from star_fact_sales fs
join star_dim_store ds
on fs.store_key = ds.store_key
group by ds.regional_manager
order by total_sales_amount desc;

-- task 22: warehouse architecture audit
-- count records in all star and snowflake tables
select 'star schema' as schema_type,'star_dim_store' as table_name,
count(*) as record_count
from star_dim_store
union all
select 'star schema','star_dim_product',
count(*)
from star_dim_product
union all
select 'star schema','star_fact_sales',
count(*)
from star_fact_sales
union all
select 'snowflake schema','snow_dim_region',
count(*)
from snow_dim_region
union all
select 'snowflake schema','snow_dim_store',
count(*)
from snow_dim_store
union all
select 'snowflake schema','snow_dim_category',
count(*)
from snow_dim_category
union all
select 'snowflake schema','snow_dim_subcategory',
count(*)
from snow_dim_subcategory
union all
select 'snowflake schema','snow_dim_product',
count(*)
from snow_dim_product
union all
select 'snowflake schema','snow_fact_sales',
count(*)
from snow_fact_sales
order by schema_type,table_name;