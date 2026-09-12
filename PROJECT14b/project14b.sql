-- create database
create database if not exists financial_gateway_db;

-- select database
use database financial_gateway_db;

-- create schema
create schema if not exists lakehouse;

-- select schema
use schema lakehouse;

-- task 1: bronze layer setup & ingestion
-- create bronze table to store raw json payloads
create or replace table bronze_payment_payloads (
    raw_payload variant
);

-- insert all 8 raw json records
-- insert 8 raw json records into bronze table
insert into bronze_payment_payloads (raw_payload)
select parse_json(column1)
from values
('{"txn_id":"txn-901","txn_time":"2026-07-10t10:00:00z","merchant_id":301,"merchant_name":"techzone","card_number":"4111222233334444","amount":50000.00,"fee_pct":2.5,"status":"approved"}'),
('{"txn_id":"txn-902","txn_time":"2026-07-10t10:15:00z","merchant_id":302,"merchant_name":"stylehub","card_number":"5500111122223333","amount":12000.00,"fee_pct":3.0,"status":"approved"}'),
('{"txn_id":"txn-903","txn_time":"2026-07-10t11:00:00z","merchant_id":301,"merchant_name":"techzone","card_number":"4111222233334444","amount":25000.00,"fee_pct":2.5,"status":"pending"}'),
('{"txn_id":"txn-904","txn_time":"2026-07-10t11:30:00z","merchant_id":303,"merchant_name":"freshmart","card_number":"4000111122223333","amount":8500.00,"fee_pct":1.8,"status":"approved"}'),
('{"txn_id":"txn-905","txn_time":"2026-07-10t12:00:00z","merchant_id":302,"merchant_name":"stylehub","card_number":"5500111122223333","amount":45000.00,"fee_pct":3.0,"status":"declined"}'),
('{"txn_id":"txn-906","txn_time":"2026-07-10t12:30:00z","merchant_id":301,"merchant_name":"techzone","card_number":"4111222233334444","amount":150000.00,"fee_pct":2.5,"status":"approved"}'),
('{"txn_id":"txn-907","txn_time":"2026-07-10t13:00:00z","merchant_id":303,"merchant_name":"freshmart","card_number":"4000111122223333","amount":3200.00,"fee_pct":1.8,"status":"approved"}'),
('{"txn_id":"txn-908","txn_time":"2026-07-10t13:15:00z","merchant_id":302,"merchant_name":"stylehub","card_number":"5500111122223333","amount":67000.00,"fee_pct":3.0,"status":"pending"}');

-- check bronze record count
select count(*) as total_bronze_records_ct
from bronze_payment_payloads;

-- task 2: silver layer etl & fee calculations
-- create silver table
create or replace table silver_cleaned_transactions (
txn_id varchar,txn_time timestamp_tz,merchant_id number,merchant_name varchar,masked_card varchar,
gross_amount number(18,2),fee_pct number(5,2),
processing_fee number(18,2),net_settlement_amount number(18,2),
status varchar
);

-- extract json fields from bronze
-- mask the card number
-- calculate processing fee
-- calculate net settlement amount
-- insert cleaned records into silver table

insert into silver_cleaned_transactions
select
    raw_payload:txn_id::varchar as txn_id,

    -- convert json timestamp to snowflake timestamp
    to_timestamp_tz(
        raw_payload:txn_time::varchar,
        'yyyy-mm-dd"t"hh24:mi:ss"z"'
    ) as txn_time,

    -- merchant information
    raw_payload:merchant_id::number as merchant_id,
    raw_payload:merchant_name::varchar as merchant_name,

    -- mask card number and show only last 4 digits
    'xxxx-xxxx-xxxx-' ||
    right(raw_payload:card_number::varchar, 4) as masked_card,

    -- transaction amount
    raw_payload:amount::number(18,2) as gross_amount,

    -- gateway fee percentage
    raw_payload:fee_pct::number(5,2) as fee_pct,

    -- calculate processing fee
    round(
        raw_payload:amount::number(18,2) *
        (raw_payload:fee_pct::number(5,2) / 100),
        2
    ) as processing_fee,

    -- calculate net settlement amount
    round(
        raw_payload:amount::number(18,2) -
        (
            raw_payload:amount::number(18,2) *
            (raw_payload:fee_pct::number(5,2) / 100)
        ),
        2
    ) as net_settlement_amount,

    -- transaction status
    raw_payload:status::varchar as status

from bronze_payment_payloads;

-- display silver data
select txn_id,merchant_id,merchant_name,masked_card,gross_amount,processing_fee,net_settlement_amount,status
from silver_cleaned_transactions
order by txn_id;

-- task 3: gold layer financial aggregations
-- create gold table containing only approved transactions
create or replace table gold_merchant_settlements as
select merchant_id,merchant_name,
-- total approved transaction amount
sum(gross_amount) as total_approved_gross,
-- total gateway fees
sum(processing_fee) as total_gateway_fees,
-- total amount paid to merchant
sum(net_settlement_amount) as total_net_payout,
-- number of approved transactions
count(*) as approved_count
from silver_cleaned_transactions
where status = 'approved'
group by merchant_id,merchant_name;

-- display gold aggregation
select * from gold_merchant_settlements
order by merchant_id;

-- task 4: data corruption simulation & time-travel inspection
-- first save the current timestamp before corruption
set before_corruption = current_timestamp();

-- intentionally corrupt techzone approved transactions
update silver_cleaned_transactions
set status = 'refunded'
where merchant_name = 'techzone'
and status = 'approved';

-- check the corrupted records
select txn_id,merchant_name,gross_amount,status
from silver_cleaned_transactions
where merchant_name = 'techzone';

-- inspect the table before the corruption using time travel
-- see the data before the corruption
select txn_id,merchant_name,gross_amount,status
from silver_cleaned_transactions
before(statement => '01c6f044-000d-f74a-0001-b0c200206a8e')
where merchant_name = 'techzone'
and status = 'approved';

-- task 5: time-travel recovery
-- restore the corrupted techzone records
-- using the transaction ids that were approved before corruption
update silver_cleaned_transactions
set status = 'approved'
where txn_id in (select txn_id
from silver_cleaned_transactions
before(statement => last_query_id())
where merchant_name = 'techzone'
and status = 'approved'
);

-- validate the recovery
select merchant_name,sum(case when status = 'approved' then 1 else 0 end) as approved_count,
sum(case when status = 'refunded' then 1 else 0 end) as refunded_count
from silver_cleaned_transactions
where merchant_name = 'techzone'
group by merchant_name;

-- task 6: end-to-end pipeline reconciliation audit
-- compare gross totals across bronze, silver and gold
select 
(select 
sum(raw_payload:amount::number(18,2))
from bronze_payment_payloads
) as bronze_gross_sum,
(select sum(gross_amount)
from silver_cleaned_transactions
) as silver_gross_sum,
(select sum(total_approved_gross)
from gold_merchant_settlements
) as gold_gross_sum,
case
when (select sum(raw_payload:amount::number(18,2))
from bronze_payment_payloads)=(select sum(gross_amount)
from silver_cleaned_transactions
)
then true
else false
end as data_match_flag;