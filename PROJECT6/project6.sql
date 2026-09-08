-- PHASE 1: CREATE WAREHOUSE, DATABASE AND SCHEMA
-- Create a small warehouse for running queries
create warehouse retail_snow_wh
warehouse_size='xsmall'
auto_suspend=60
auto_resume=true;

-- Create the retail database
create database retail_snow_db;

-- Create schema inside the retail database
create schema retail_snow_db.retail_snow_schema;

-- Select the database and schema
use database retail_snow_db;
use schema retail_snow_schema;

-- PHASE 2: CREATE FILE FORMAT AND STAGE
-- Define CSV file format for loading source files
create file format csv_format
type=csv
field_delimiter=','
skip_header=1
field_optionally_enclosed_by='"'
null_if=('NULL','null');

-- Create an internal stage to store CSV files
create stage retail_stage file_format=csv_format;

-- PHASE 3: CREATE SNOWFLAKE SCHEMA
-- Store region information
create table dim_region(
region_id int primary key,region_name varchar(50)
);

-- Store state information and connect states to regions
create table dim_state(
state_id int primary key,state_name varchar(25),
region_id int,foreign key (region_id) references dim_region(region_id)
);

-- Store city information and connect cities to states
create table dim_city(
city_id int primary key,city_name varchar(35),
state_id int,foreign key (state_id) references dim_state(state_id)
);

-- Store product category information
create table dim_category(
category_id int primary key,category_name varchar(35)
);

-- Store brand information and connect brands to categories
create table dim_brand(
brand_id int primary key,brand_name varchar(50),
category_id int,foreign key (category_id) references dim_category(category_id)
);

-- Store year information
create table year(
year_id int primary key,year_value int
);

-- Store quarter information and connect it to year
create table quarter(
quarter_id int primary key,quarter_name varchar(50),
year_id int,foreign key (year_id) references year(year_id)
);

-- Store month information and connect it to quarter
create table month(
month_id int primary key,month_name varchar(20),
quarter_id int,foreign key (quarter_id) references quarter(quarter_id)
);

-- Store customer information
create table dim_customer(
customer_id int primary key,customer_name varchar(100),
city_id int,membership varchar(50),
foreign key (city_id) references dim_city(city_id)
);

-- Store product information
create table dim_product(
product_id int primary key,product_name varchar(100),
brand_id int,price decimal(15,2),
foreign key (brand_id) references dim_brand(brand_id)
);

-- Store branch information
create table dim_branch(
branch_id int primary key,branch_name varchar(100),
city_id int,manager_name varchar(100),
foreign key (city_id) references dim_city(city_id)
);

-- Store date information
create table dim_date(
date_id int primary key,date date,
day int,day_name varchar(20),
week_no int,month_id int,is_weekend varchar(10),
foreign key (month_id) references month(month_id)
);

-- Fact table containing sales transactions
create table fact_sales(
sale_id int primary key,customer_id int,
product_id int,branch_id int,date_id int,
quantity int,total_amount decimal(15,2),
-- Connect sales to dimension tables
foreign key (customer_id) references dim_customer(customer_id),
foreign key (product_id) references dim_product(product_id),
foreign key (branch_id) references dim_branch(branch_id),
foreign key (date_id) references dim_date(date_id)
);

-- PHASE 4: CREATE SOURCE TABLES
-- Source customer data
CREATE TABLE CUSTOMERS (
CUSTOMER_ID INT,CUSTOMER_NAME VARCHAR,
CITY VARCHAR,STATE VARCHAR,
MEMBERSHIP VARCHAR
);

-- Source product data
CREATE TABLE PRODUCTS (
PRODUCT_ID INT,PRODUCT_NAME VARCHAR,
CATEGORY VARCHAR,BRAND VARCHAR,PRICE NUMBER(12,2)
);

-- Source branch data
CREATE TABLE BRANCHES (
BRANCH_ID INT,BRANCH_NAME VARCHAR,
CITY VARCHAR,STATE VARCHAR,
REGION VARCHAR,MANAGER_NAME VARCHAR
);

-- Source calendar data
CREATE TABLE CALENDAR (
DATE_ID INT,DATE DATE,DAY INT,
DAY_NAME VARCHAR,WEEK_NO INT,MONTH VARCHAR,
QUARTER VARCHAR,YEAR INT,IS_WEEKEND VARCHAR
);

-- Source sales transactions
CREATE TABLE SALES (
SALE_ID INT,CUSTOMER_ID INT,PRODUCT_ID INT,BRANCH_ID INT,
DATE_ID INT,QUANTITY INT,TOTAL_AMOUNT NUMBER(12,2)
);

-- PHASE 5: LOAD CSV DATA
-- Load customer CSV file
copy into customers
from @retail_stage/customers.csv
file_format=csv_format;
-- Load product CSV file
copy into products
from @retail_stage/products.csv
file_format=csv_format;

-- Load branch CSV file
copy into branches
from @retail_stage/branches.csv
file_format=csv_format;

-- Load calendar CSV file
copy into calendar
from @retail_stage/calendar.csv
file_format=csv_format;

-- Load sales CSV file
copy into fact_sales
from @retail_stage/sales.csv
file_format=csv_format;

-- PHASE 6: LOAD NORMALIZED DIMENSION TABLES
-- Insert unique regions and assign region IDs
insert into dim_region(region_id,region_name)
select distinct
    case region
        when 'North' then 1
        when 'South' then 2
        when 'East' then 3
        when 'West' then 4
    end,
    region
from branches;

-- View region data
select * from dim_region;

-- Insert states and connect them to regions
insert into dim_state(state_id,state_name,region_id)
select distinct
    case state
        when 'Telangana' then 1
        when 'Karnataka' then 2
        when 'Tamil Nadu' then 3
        when 'Maharashtra' then 4
        when 'Delhi' then 5
        when 'Gujarat' then 6
        when 'West Bengal' then 7
        when 'Rajasthan' then 8
        when 'Kerala' then 9
        when 'Uttar Pradesh' then 10
        when 'Andhra Pradesh' then 11
        when 'Bihar' then 12
        when 'Madhya Pradesh' then 13
        when 'Chandigarh' then 14
    end as state_id,
    state,
    case state
        -- Assign each state to its region
        WHEN 'Telangana' THEN 2
        WHEN 'Karnataka' THEN 2
        WHEN 'Tamil Nadu' THEN 2
        WHEN 'Maharashtra' THEN 4
        WHEN 'Delhi' THEN 1
        WHEN 'Gujarat' THEN 4
        WHEN 'West Bengal' THEN 3
        WHEN 'Rajasthan' THEN 1
        WHEN 'Kerala' THEN 2
        WHEN 'Uttar Pradesh' THEN 1
        WHEN 'Andhra Pradesh' THEN 2
        WHEN 'Bihar' THEN 1
        WHEN 'Madhya Pradesh' THEN 1
        WHEN 'Chandigarh' THEN 1
    end as region_id
from branches;


-- Create unique city IDs and connect cities to states
insert into dim_city(city_id,city_name,state_id)
select distinct
    row_number() over(order by city),
    city,
    s.state_id
from branches b
join dim_state s
    on b.state=s.state_name;

-- Create product categories
insert into dim_category(category_id,category_name)
select distinct row_number() over(order by category),
category from products;

-- Create brands and connect them to categories
insert into dim_brand(brand_id,brand_name,category_id)
select row_number() over(order by p.brand),p.brand,
c.category_id from products p
join dim_category c on p.category=c.category_name;

-- CREATE DATE HIERARCHY
-- Insert years into year dimension
insert into year(year_id,year_value)
select distinct year,year
from calendar;

-- Insert quarters and connect them to years
insert into quarter(quarter_id,quarter_name,year_id)
select distinct
    case quarter
        when 'Q1' then 1
        when 'Q2' then 2
        when 'Q3' then 3
        when 'Q4' then 4
    end,
    quarter,
    year
from calendar;

-- Insert months and connect them to quarters
insert into month (month_id, month_name, quarter_id)
select distinct
    case
        when month = 'January' then 1
        when month = 'February' then 2
        when month = 'March' then 3
        when month = 'April' then 4
        when month = 'May' then 5
        when month = 'June' then 6
        when month = 'July' then 7
        when month = 'August' then 8
        when month = 'September' then 9
        when month = 'October' then 10
        when month = 'November' then 11
        when month = 'December' then 12
    end as month_id,
    month as month_name,
    case
        when quarter = 'Q1' then 1
        when quarter = 'Q2' then 2
        when quarter = 'Q3' then 3
        when quarter = 'Q4' then 4
    end as quarter_id
from calendar;

-- VIEW NORMALIZED DIMENSIONS
-- Check region dimension
select * from dim_region;

-- Check state dimension
select * from dim_state;

-- Check city dimension
select * from dim_city;

-- Check category dimension
select * from dim_category;

-- Check brand dimension
select * from dim_brand;

-- Check year dimension
select * from year;

-- Check month dimension
select * from month;

-- Check quarter dimension
select * from quarter;

-- LOAD REMAINING DIMENSION TABLES
-- Load customers and connect them to cities
insert into dim_customer(customer_id,customer_name,city_id,membership)
select c.customer_id,c.customer_name,ci.city_id,
c.membership from customers c
join dim_city ci
on c.city=ci.city_name;

-- Load products and connect them to brands
insert into dim_product(product_id,product_name,brand_id,price)
select p.product_id,p.product_name,b.brand_id,p.price
from products p join dim_brand b
on p.brand=b.brand_name;

-- Load branches and connect them to cities
insert into dim_branch(branch_id,branch_name,city_id,manager_name)
select b.branch_id,b.branch_name,c.city_id,b.manager_name
from branches b join dim_city c
on b.city=c.city_name;

-- Load dates and connect them to months
insert into dim_date(
    date_id,date,day,day_name,week_no,month_id,is_weekend
)
select
    c.date_id,
    c.date,
    c.day,
    c.day_name,
    c.week_no,
    m.month_id,
    c.is_weekend
from calendar c
join month m
    on c.month=m.month_name;

-- View loaded dimensions
select * from dim_customer;
select * from dim_product;
select * from dim_branch;
select * from dim_date;

-- PHASE 5: VALIDATE FACT TABLE RELATIONSHIPS
-- Check for sales records with missing customers
select count(*) as unmatched_customers
from fact_sales f
left join dim_customer c
on f.customer_id=c.customer_id
where c.customer_id is null;

-- Check for sales records with missing products
select count(*) as unmatched_products
from fact_sales f
left join dim_product p
on f.product_id=p.product_id
where p.product_id is null;

-- Check for sales records with missing branches
select count(*) as unmatched_branches
from fact_sales f
left join dim_branch b
on f.branch_id=b.branch_id
where b.branch_id is null;

-- Check for sales records with missing dates
select count(*) as unmatched_dates
from fact_sales f
left join dim_date d
on f.date_id=d.date_id
where d.date_id is null;

-- All four validation queries should return 0
-- OVERALL FACT TABLE VALIDATION
-- Display overall sales and dimension statistics
select count(*) as total_Sales,
count(distinct customer_id) as customers,
count(distinct product_id) as products,
count(distinct branch_id) as branches,
count(distinct date_id) as dates
from fact_sales;

-- Count total sales transactions
select count(*) from fact_sales;

-- BUSINESS REPORTS
-- Customer-wise total sales
select c.customer_id,c.customer_name,sum(f.total_amount) as total_sales
from dim_customer c
join fact_sales f
on c.customer_id=f.customer_id
group by c.customer_id,c.customer_name
order by total_sales desc;

-- Product-wise total revenue
select p.product_id,p.product_name,sum(f.total_amount) as total_sales
from dim_product p
join fact_sales f
on p.product_id=f.product_id
group by p.product_id,p.product_name
order by total_sales desc;

-- Brand-wise total revenue
select b.brand_id,b.brand_name,sum(f.total_amount) as total_revenue
from dim_product p
join fact_sales f
on p.product_id=f.product_id
join dim_brand b
on b.brand_id=p.brand_id
group by b.brand_id,b.brand_name
order by total_revenue desc;

-- Category-wise total revenue
select c.category_id,c.category_name,sum(f.total_amount) as total_revenue
from dim_product p
join fact_sales f
on p.product_id=f.product_id
join dim_brand b
on b.brand_id=p.brand_id
join dim_category c
on b.category_id=c.category_id
group by c.category_id,c.category_name
order by total_revenue desc;

-- City-wise total revenue
select d.city_id,d.city_name,sum(f.total_amount) as total_revenue
from dim_customer c
join fact_sales f
on f.customer_id=c.customer_id
join dim_city d
on c.city_id=d.city_id
group by d.city_id,d.city_name
order by total_revenue desc;

-- State-wise total revenue
select s.state_id,s.state_name,sum(f.total_amount) as total_revenue
from dim_customer c
join fact_sales f
on c.customer_id=f.customer_id
join dim_city d
on c.city_id=d.city_id
join dim_state s
on d.state_id=s.state_id
group by s.state_id,s.state_name
order by total_revenue desc;


-- Region-wise total revenue
select r.region_id,r.region_name,sum(f.total_amount) as total_revenue
from dim_branch b
join fact_sales f
on b.branch_id=f.branch_id
join dim_city c
on c.city_id=b.city_id
join dim_state s
on c.state_id=s.state_id
join dim_region r
on s.region_id=r.region_id
group by r.region_id,r.region_name
order by total_revenue desc;

-- Monthly revenue report
select m.month_id,m.month_name,sum(f.total_amount) as total_revenue
from dim_date d
join fact_sales f
on d.date_id=f.date_id
join month m
on d.month_id=m.month_id
group by m.month_id,m.month_name
order by total_revenue desc;

-- Quarterly revenue report
select q.quarter_id,q.quarter_name,sum(f.total_amount) as total_revenue
from dim_date d
join fact_sales f
on d.date_id=f.date_id
join month m
on d.month_id=m.month_id
join quarter q
on m.quarter_id=q.quarter_id
group by q.quarter_id,q.quarter_name
order by total_revenue desc;

-- TOP 10 ANALYTICS
-- Find the top 10 customers by revenue
select c.customer_id,c.customer_name,sum(f.total_amount) as total_revenue
from dim_customer c
join fact_sales f
on c.customer_id=f.customer_id
group by c.customer_id,c.customer_name
order by total_revenue desc
limit 10;

-- Find the top 10 products by sales
select p.product_id,p.product_name,sum(f.total_amount) as total_sales
from dim_product p
join fact_sales f
on p.product_id=f.product_id
group by p.product_id,p.product_name
order by total_sales desc
limit 10;

-- Find the top 10 branches by revenue
select b.branch_id,b.branch_name,sum(f.total_amount) as total_revenue
from dim_branch b
join fact_sales f
on b.branch_id=f.branch_id
group by b.branch_id,b.branch_name
order by total_revenue desc
limit 10;

-- CUSTOMER PURCHASE TREND
-- Show customer purchases and revenue month-wise
select c.customer_id,c.customer_name,m.month_name,count(f.sale_id) as purchase_count,sum(f.total_amount) as total_revenue
from dim_customer c
join fact_sales f
on c.customer_id=f.customer_id
join dim_date d
on f.date_id=d.date_id
join month m
on d.month_id=m.month_id
group by c.customer_id,c.customer_name,m.month_name
order by total_revenue;

-- PRODUCT PERFORMANCE DASHBOARD
-- Display product transactions, units sold and revenue
select p.product_id,p.product_name,b.brand_name,c.category_name,count(f.sale_id) as total_transactions,
sum(f.quantity) as units_sold,sum(f.total_amount) as total_revenue
from dim_product p
join fact_sales f
on p.product_id=f.product_id
join dim_brand b
on p.brand_id=b.brand_id
join dim_category c
on b.category_id=c.category_id
group by p.product_id,p.product_name,b.brand_name,c.category_name
order by total_revenue desc;

-- Show customers, orders, quantity and sales for each region
select r.region_id,r.region_name,count(distinct c.customer_id) as number_of_customers,count(f.sale_id) as number_of_orders,
sum(f.quantity) as quantity_sold,sum(f.total_amount) as total_sales
from dim_customer c
join fact_sales f
on c.customer_id=f.customer_id
join dim_city d
on c.city_id=d.city_id
join dim_state s
on s.state_id=d.state_id
join dim_region r
on r.region_id=s.region_id
group by r.region_id,r.region_name
order by total_sales desc;