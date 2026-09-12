-- task 1: create database and schema
-- create the database
create database if not exists logistics_lakehouse_db;

-- use the database
use database logistics_lakehouse_db;

-- create the schema
create schema if not exists fleet_core;

-- use the schema
use schema fleet_core;

-- create bronze table
-- bronze stores the raw json payload
create or replace table bronze_iot_streams (
    ingest_id number,
    raw_payload variant,
    recorded_at timestamp_tz
);

-- create json file format
create or replace file format fleet_json_format
    type = json
    strip_outer_array = true;

-- create a stage for uploading the batch json file
create or replace stage fleet_iot_stage
    file_format = fleet_json_format;

-- upload your batch json file to this stage using snowflake ui
-- after uploading, run this command
list @fleet_iot_stage;

-- load the json records from the stage
insert into bronze_iot_streams (
ingest_id,raw_payload,recorded_at
)
select row_number() over (order by metadata$filename, metadata$file_row_number) as ingest_id,
$1 as raw_payload,
current_timestamp() as recorded_at
from @fleet_iot_stage (file_format => 'fleet_json_format');

-- display bronze records
select * from bronze_iot_streams
order by ingest_id;

-- expected record count = 8
select count(*) as bronze_record_count
from bronze_iot_streams;

-- extract fields directly from the variant json column
select raw_payload:payload_id::varchar as payload_id,
raw_payload:payload_type::varchar as payload_type,
raw_payload:timestamp::varchar as event_timestamp,
raw_payload:data:vehicle_id::varchar as vehicle_id,
raw_payload:data:shipment_id::varchar as shipment_id,
raw_payload:data:destination_country::varchar as destination_country,
raw_payload:data:declared_value::number(18,2) as declared_value
from bronze_iot_streams
order by ingest_id;

-- task 2: create quarantine table
-- create a table for malformed json records
create or replace table quarantine_iot_payloads (
quarantine_id number,raw_record_text varchar,reason varchar);


-- insert the malformed record into quarantine
-- try_parse_json returns null for invalid json
insert into quarantine_iot_payloads (
quarantine_id,raw_record_text,reason
)
select 1,'MALFORMED_IOT_SENSOR_BINARY_BURST_DATA_ERR','MALFORMED_JSON_BODY'
where try_parse_json('MALFORMED_IOT_SENSOR_BINARY_BURST_DATA_ERR') is null;

-- verify quarantine
select * from quarantine_iot_payloads;

-- task 3: create silver customs table
-- silver contains cleaned and structured customs data
create or replace table silver_customs_clearance (
shipment_id varchar,payload_id varchar,vehicle_id varchar,
destination_country varchar,declared_value number(18,2),duty_pct number(5,2),
duty_amount_due number(18,2),border_code varchar,clearance_status varchar
);

-- extract customs records from bronze
-- calculate the duty amount
insert into silver_customs_clearance (
shipment_id,payload_id,vehicle_id,destination_country,
declared_value,duty_pct,duty_amount_due,border_code,clearance_status
)
select raw_payload:data:shipment_id::varchar as shipment_id,
raw_payload:payload_id::varchar as payload_id,raw_payload:data:vehicle_id::varchar as vehicle_id,
raw_payload:data:destination_country::varchar as destination_country,
raw_payload:data:declared_value::number(18,2) as declared_value,
raw_payload:data:duty_pct::number(5,2) as duty_pct,
round(raw_payload:data:declared_value::number(18,2)* raw_payload:data:duty_pct::number(5,2)/ 100,2) as duty_amount_due,
raw_payload:data:border_clearance_code::varchar as border_code,
raw_payload:data:clearance_status::varchar as clearance_status
from bronze_iot_streams
where raw_payload:payload_type::varchar = 'CUSTOMS';

-- verify silver table
select * from silver_customs_clearance
order by shipment_id;

-- task 4: create gold table
-- gold contains country-level customs analytics
create or replace table gold_country_duty_summary (
destination_country varchar,total_declared_value number(18,2),
total_duty_amount number(18,2),avg_duty_rate_pct number(10,2),cleared_shipments number
);

-- include only cleared shipments
insert into gold_country_duty_summary (
destination_country,total_declared_value,total_duty_amount,
avg_duty_rate_pct,cleared_shipments
)
select destination_country,sum(declared_value) as total_declared_value,
sum(duty_amount_due) as total_duty_amount,
round(sum(duty_amount_due)/ nullif(sum(declared_value), 0)* 100,2) as avg_duty_rate_pct,
count(*) as cleared_shipments
from silver_customs_clearance
where clearance_status = 'CLEARED'
group by destination_country
order by destination_country;

-- verify gold table
select * from gold_country_duty_summary;

-- task 5: simulate data corruption
-- intentionally change all canadian records
update silver_customs_clearance
set clearance_status = 'REJECTED'
where destination_country = 'CAN';

-- run this immediately after the update
select last_query_id();

-- replace the query id below with your actual update query id
select shipment_id,destination_country,declared_value,clearance_status
from silver_customs_clearance
before (
    statement => '01c6f328-000d-f74a-0001-b0c2002168e2'
)
where destination_country = 'CAN';

-- restore the canadian records
update silver_customs_clearance
set clearance_status = 'CLEARED'
where destination_country = 'CAN'
and clearance_status = 'REJECTED';

-- verify recovery
select destination_country,clearance_status,count(*) as record_count
from silver_customs_clearance
group by destination_country,clearance_status
order by destination_country,clearance_status;

-- task 6: bronze reconciliation
-- calculate customs declared value from bronze
select sum(raw_payload:data:declared_value::number(18,2)) as bronze_customs_value
from bronze_iot_streams
where raw_payload:payload_type::varchar = 'CUSTOMS';

-- calculate customs declared value from silver
select sum(declared_value) as silver_customs_value
from silver_customs_clearance;

-- gold contains only cleared shipments
select sum(total_declared_value) as gold_cleared_value
from gold_country_duty_summary;

-- compare bronze and silver totals
select b.bronze_customs_value,s.silver_customs_value,
case
when b.bronze_customs_value = s.silver_customs_value
then true
else false
end as reconciled
from (select sum(raw_payload:data:declared_value::number(18,2)) as bronze_customs_value
from bronze_iot_streams
where raw_payload:payload_type::varchar = 'CUSTOMS'
) b
cross join
(select sum(declared_value) as silver_customs_value
from silver_customs_clearance
) s;