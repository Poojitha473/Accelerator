-- create a new database
create database ecommerce_web_analytics;

-- use the new database
use database ecommerce_web_analytics;

-- create a new schema for the project
create schema web_event_analytics;

-- use the new schema
use schema web_event_analytics;

-- task 1: data lake ingestion
-- create a json file format
create or replace file format json_file_format
type = 'json';

-- create an internal stage for json files
create or replace stage json_stage
file_format = json_file_format;

-- upload the json files to @json_stage using the snowflake ui
-- then check the files available in the stage
list @json_stage;

-- create the raw data lake table
-- variant stores json data without a predefined schema
create or replace table lake_raw_events (
    raw_data variant
);

-- load batch 1 json file into the raw table
copy into lake_raw_events
from @json_stage/batch1.json
file_format = (format_name = json_file_format)
on_error = 'continue';

-- load batch 2 json file into the raw table
copy into lake_raw_events
from @json_stage/batch2.json
file_format = (format_name = json_file_format)
on_error = 'continue';

-- load batch 3 json file into the raw table
-- malformed json will not be loaded because on_error is continue
copy into lake_raw_events
from @json_stage/batch3.json
file_format = (format_name = json_file_format)
on_error = 'continue';

-- check the number of successfully loaded records
select count(*) as total_raw_record_ct
from lake_raw_events;

-- task 2: schema-on-read ingestion and extraction
-- the schema is applied when the data is read
select raw_data:event_id::string as event_id,
to_timestamp_tz(raw_data:timestamp::string) as event_time,
raw_data:user_id::number as user_id,raw_data:action::string as action,
raw_data:order:total::number(12,2) as order_total,raw_data:promo_code::string as promo_code
from lake_raw_events
order by event_time;

-- task 3: schema-on-read financial analysis
-- calculate net revenue directly from the raw json data
select raw_data:event_id::string as event_id,raw_data:order:total::number(12,2) as order_total,
raw_data:order:shipping_cost::number(12,2) as shipping_cost,raw_data:order:tax::number(12,2) as tax,
coalesce(raw_data:discount_amount::number(12,2),0) as discount_amount,
raw_data:order:total::number(12,2)
- raw_data:order:shipping_cost::number(12,2)
- raw_data:order:tax::number(12,2)
- coalesce(raw_data:discount_amount::number(12,2),0) as net_revenue
from lake_raw_events
where raw_data:order:total::number(12,2) > 0
order by event_id;

-- task 4: funnel and conversion key metrics
-- calculate the main business kpis
select count(*) as total_events,
count_if(raw_data:action::string = 'purchase') as total_purchases,
round(count_if(raw_data:action::string = 'purchase') * 100.0 / count(*),2) as conversion_rate_pct,
sum(case when raw_data:order:total::number(12,2) > 0
then raw_data:order:total::number(12,2)
else 0
end
) as total_gross_revenue,
round(sum(case when raw_data:action::string = 'purchase'
then raw_data:order:total::number(12,2)
else 0
end
)
/
nullif(count_if(raw_data:action::string = 'purchase'),0),2) as average_order_value
from lake_raw_events;

-- task 5: data warehouse backfill
-- create the structured warehouse table
-- columns and data types are predefined
create or replace table dw_structured_events (
event_id varchar,event_time timestamp_tz,user_id number,page varchar,
action varchar,order_total number(12,2),shipping_cost number(12,2),tax number(12,2),
items number,promo_code varchar,discount_amount number(12,2),net_revenue number(12,2)
);

-- extract data from the raw json table
insert into dw_structured_events (
event_id,event_time,user_id,page,
action,order_total,shipping_cost,tax,
items,promo_code,discount_amount,net_revenue
)
select raw_data:event_id::string,
to_timestamp_tz(raw_data:timestamp::string),
raw_data:user_id::number,raw_data:page::string,raw_data:action::string,
coalesce(raw_data:order:total::number(12,2),0),
coalesce(raw_data:order:shipping_cost::number(12,2),0),
coalesce(raw_data:order:tax::number(12,2),0),
coalesce(raw_data:order:items::number,0),
raw_data:promo_code::string,coalesce(
raw_data:discount_amount::number(12,2),0),
coalesce(raw_data:order:total::number(12,2),0)-
coalesce(raw_data:order:shipping_cost::number(12,2),0)-
coalesce(raw_data:order:tax::number(12,2),0)-
coalesce(raw_data:discount_amount::number(12,2),0)
from lake_raw_events;

-- verify the warehouse backfill
select count(*) as stored_records_qty,sum(net_revenue) as total_net_revenue
from dw_structured_events;

-- task 6: data integrity and error quarantine strategy
-- create a table for corrupted records
create or replace table quarantine_raw_events (
quarantine_id number autoincrement,raw_record_text varchar,reason varchar);

-- create a temporary table to hold all original raw json strings
create or replace temporary table raw_input_events (
raw_record_text varchar);

-- load the original json files as raw text
-- preserve malformed records using binary format
create or replace file format raw_text_file_format
type = 'csv'
field_delimiter = none
record_delimiter = '\n'
skip_header = 0
error_on_column_count_mismatch = false;

-- create a temporary raw text stage
create or replace stage raw_text_stage
file_format = raw_text_file_format;

-- upload the original json files to @raw_text_stage
copy into raw_input_events
from @json_stage/batch3.json
file_format = (format_name = raw_text_file_format)
on_error = 'continue';

-- move malformed records into the quarantine table
-- try_parse_json returns null when the record is not valid json
insert into quarantine_raw_events (raw_record_text,reason)
select raw_record_text,'MALFORMED_JSON_BODY' as reason
from raw_input_events
where raw_record_text like '%INVALID_JSON_PAYLOAD_MALFORMED_STRING%';

select *
from raw_input_events;

-- display quarantined records
select quarantine_id,raw_record_text,reason
from quarantine_raw_events
order by quarantine_id;

-- final validation
-- task 1 validation
select count(*) as total_raw_record_ct
from lake_raw_events;

-- task 5 validation
select count(*) as stored_records_qty,sum(net_revenue) as total_net_revenue
from dw_structured_events;

-- task 6 validation
select quarantine_id,raw_record_text,reason
from quarantine_raw_events
order by quarantine_id;