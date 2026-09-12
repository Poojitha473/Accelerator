-- task 1: create environment context
-- create the healthcare database
create database if not exists healthcare_dw;

-- use the healthcare database
use database healthcare_dw;

-- create the comparison schema
create schema if not exists schema_compare_lab;

-- use the comparison schema
use schema schema_compare_lab;

-- create a csv file format for the source files
create or replace file format healthcare_csv_format
type = csv
field_delimiter = ','
skip_header = 1
field_optionally_enclosed_by = '"'
null_if = ('null', '');

-- create an internal stage
create or replace stage healthcare_stage
file_format = healthcare_csv_format;

-- check the uploaded files
list @healthcare_stage;

-- create source table for hospital hierarchy
create or replace table hospital_hierarchy (
hospital_id number,hospital_name varchar(100),city varchar(50),
state varchar(50),network_id number,network_name varchar(100),network_director varchar(100)
);

-- create source table for treatment hierarchy
create or replace table treatment_hierarchy (
treatment_id number,treatment_name varchar(100),diagnosis_group_id varchar(50),
diagnosis_group_name varchar(50),standard_cost number(12,2)
);

-- create source table for patients
create or replace table patients (
patient_id number,patient_name varchar(100),
gender varchar(20),age number,city varchar(50)
);

-- create source table for insurance claims
create or replace table insurance_claims (
claim_id varchar(50),claim_date date,
patient_id number,hospital_id number,
treatment_id number,claimed_amount number(12,2),approved_amount number(12,2)
);

copy into hospital_hierarchy
from @healthcare_stage/hospital_hierarchy.csv
file_format = (
    format_name = healthcare_csv_format
)
on_error = 'abort_statement';

copy into treatment_hierarchy
from @healthcare_stage/treatment_hierarchy.csv
file_format = (
    format_name = healthcare_csv_format
)
on_error = 'abort_statement';

copy into patients
from @healthcare_stage/patients.csv
file_format = (
    format_name = healthcare_csv_format
)
on_error = 'abort_statement';

copy into insurance_claims
from @healthcare_stage/insurance_claims.csv
file_format = (
    format_name = healthcare_csv_format
)
on_error = 'abort_statement';

-- check hospital source data
select * from hospital_hierarchy;

-- check treatment source data
select * from treatment_hierarchy;

-- check patient source data
select * from patients;

-- check claims source data
select * from insurance_claims;

-- task 2: build star schema denormalized hospital dimension
-- create the denormalized hospital dimension
create or replace table star_dim_hospital (
hospital_key number autoincrement primary key,hospital_id number,hospital_name varchar(100),
city varchar(50),state varchar(50),network_name varchar(100),network_director varchar(100)
);

-- verify the table
desc table star_dim_hospital;

-- task 3: build star schema denormalized treatment dimension
-- create the denormalized treatment dimension
create or replace table star_dim_treatment (
treatment_key number autoincrement primary key,treatment_id number,treatment_name varchar(100),
diagnosis_group_name varchar(50),standard_cost number(12,2)
);

-- verify the table
desc table star_dim_treatment;

-- task 4: load star schema dimension data
-- load hospital records from the uploaded source table
insert into star_dim_hospital (
hospital_id,hospital_name,city,
state,network_name,network_director
)
select hospital_id,hospital_name,city,
state,network_name,network_director
from hospital_hierarchy;

-- load treatment records from the uploaded source table
insert into star_dim_treatment (
treatment_id,treatment_name,
diagnosis_group_name,standard_cost
)
select treatment_id,treatment_name,diagnosis_group_name,standard_cost
from treatment_hierarchy;

-- verify hospital dimension
select * from star_dim_hospital
order by hospital_id;

-- verify treatment dimension
select * from star_dim_treatment
order by treatment_id;

-- task 5: build and load star schema claims fact table
-- create the star fact table
create or replace table star_fact_claims (
claim_key number autoincrement primary key,claim_id varchar(50),
claim_date date,patient_id number,hospital_key number,treatment_key number,
claimed_amount number(12,2),approved_amount number(12,2),
foreign key (hospital_key)
references star_dim_hospital(hospital_key),
foreign key (treatment_key)
references star_dim_treatment(treatment_key)
);

-- load claims from the uploaded claims source table
insert into star_fact_claims (
claim_id,claim_date,patient_id,hospital_key,treatment_key,
claimed_amount,approved_amount
)
select c.claim_id,c.claim_date,c.patient_id,h.hospital_key,t.treatment_key,
c.claimed_amount,c.approved_amount
from insurance_claims c
join star_dim_hospital h
on c.hospital_id = h.hospital_id
join star_dim_treatment t
on c.treatment_id = t.treatment_id;

-- verify star fact table
select * from star_fact_claims
order by claim_id;

-- task 6: build normalized snowflake schema hospital hierarchy
-- create the network dimension
create or replace table snow_dim_network (
network_key number autoincrement primary key,network_id number,
network_name varchar(100),network_director varchar(100)
);

-- create the normalized hospital dimension
create or replace table snow_dim_hospital (
hospital_key number autoincrement primary key,hospital_id number,hospital_name varchar(100),
city varchar(50),state varchar(50),network_key number,
foreign key (network_key)
references snow_dim_network(network_key)
);

-- verify network table
desc table snow_dim_network;

-- verify hospital table
desc table snow_dim_hospital;

-- task 7: build normalized snowflake schema treatment hierarchy
-- create the diagnosis group dimension
create or replace table snow_dim_diagnosis_group (
diagnosis_group_key number autoincrement primary key,diagnosis_group_id varchar(50),
diagnosis_group_name varchar(50)
);

-- create the normalized treatment dimension
create or replace table snow_dim_treatment (
treatment_key number autoincrement primary key,treatment_id number,treatment_name varchar(100),
standard_cost number(12,2),diagnosis_group_key number,
foreign key (diagnosis_group_key)
references snow_dim_diagnosis_group(diagnosis_group_key)
);

-- verify diagnosis group table
desc table snow_dim_diagnosis_group;

-- verify treatment table
desc table snow_dim_treatment;

-- task 8: populate snowflake schema normalized hierarchies
-- load unique networks from the uploaded hospital csv
insert into snow_dim_network (
network_id,network_name,network_director
)
select distinct
network_id,network_name,network_director
from hospital_hierarchy;

-- load hospitals and connect them to the network keys
insert into snow_dim_hospital (
hospital_id,hospital_name,city,state,network_key
)
select h.hospital_id,h.hospital_name,h.city,h.state,n.network_key
from hospital_hierarchy h
join snow_dim_network n
on h.network_id = n.network_id;

-- load unique diagnosis groups from the uploaded treatment csv
insert into snow_dim_diagnosis_group (
diagnosis_group_id,diagnosis_group_name
)
select distinct diagnosis_group_id,diagnosis_group_name
from treatment_hierarchy;

-- load treatments and connect them to diagnosis group keys
insert into snow_dim_treatment (
treatment_id,treatment_name,standard_cost,diagnosis_group_key
)
select t.treatment_id,t.treatment_name,t.standard_cost,d.diagnosis_group_key
from treatment_hierarchy t
join snow_dim_diagnosis_group d
on t.diagnosis_group_id = d.diagnosis_group_id;

-- verify network records
select * from snow_dim_network
order by network_id;

-- verify hospital records
select * from snow_dim_hospital
order by hospital_id;

-- verify diagnosis group records
select * from snow_dim_diagnosis_group
order by diagnosis_group_id;

-- verify treatment records
select * from snow_dim_treatment
order by treatment_id;

-- task 9: build and load snowflake schema claims fact table
-- create the snowflake fact table
create or replace table snow_fact_claims (
claim_key number autoincrement primary key,claim_id varchar(50),
claim_date date,patient_id number,hospital_key number,treatment_key number,
claimed_amount number(12,2),approved_amount number(12,2),
foreign key (hospital_key)
references snow_dim_hospital(hospital_key),
foreign key (treatment_key)
references snow_dim_treatment(treatment_key)
);

-- load claims from the uploaded insurance claims csv
insert into snow_fact_claims (
claim_id,claim_date,patient_id,hospital_key,
treatment_key,claimed_amount,approved_amount
)
select c.claim_id,c.claim_date,c.patient_id,h.hospital_key,t.treatment_key,
c.claimed_amount,c.approved_amount
from insurance_claims c
join snow_dim_hospital h
on c.hospital_id = h.hospital_id
join snow_dim_treatment t
on c.treatment_id = t.treatment_id;

-- verify snowflake fact table
select * from snow_fact_claims
order by claim_id;

-- task 10: star schema specialty claims analysis
select t.diagnosis_group_name,sum(f.claimed_amount) as total_claimed_amount,
sum(f.approved_amount) as total_approved_amount
from star_fact_claims f
join star_dim_treatment t
on f.treatment_key = t.treatment_key
group by
t.diagnosis_group_name
order by
t.diagnosis_group_name;

-- task 11: snowflake schema specialty claims analysis
select d.diagnosis_group_name,sum(f.claimed_amount) as total_claimed_amount,
sum(f.approved_amount) as total_approved_amount
from snow_fact_claims f
join snow_dim_treatment t
on f.treatment_key = t.treatment_key
join snow_dim_diagnosis_group d
on t.diagnosis_group_key = d.diagnosis_group_key
group by
d.diagnosis_group_name
order by
d.diagnosis_group_name;

-- task 12: hospital network director performance report
select h.network_director,count(f.claim_id) as total_claims_handled,
sum(f.approved_amount) as total_approved_amount
from star_fact_claims f
join star_dim_hospital h
on f.hospital_key = h.hospital_key
group by h.network_director
order by h.network_director;

-- network information requires an additional hierarchy join
select n.network_director,
count(f.claim_id) as total_claims_handled,
sum(f.approved_amount) as total_approved_amount
from snow_fact_claims f
join snow_dim_hospital h
on f.hospital_key = h.hospital_key
join snow_dim_network n
on h.network_key = n.network_key
group by n.network_director
order by n.network_director;

-- task 13: data anomaly analysis
-- update the two hospital records in the star schema
update star_dim_hospital
set network_director = 'Dr. Anand'
where network_name = 'Apollo Healthcare Group';

-- verify the star schema update
select 'Star Schema' as schema_type,
'STAR_DIM_HOSPITAL' as updated_table,
count(*) as rows_updated,
'Higher (Multiple rows)' as maintenance_effort
from star_dim_hospital
where network_name = 'Apollo Healthcare Group'
and network_director = 'Dr. Anand';

-- update the single network record in the snowflake schema
update snow_dim_network
set network_director = 'Dr. Anand'
where network_id = 10;

-- verify the snowflake schema update
select 'Snowflake Schema' as schema_type,
'SNOW_DIM_NETWORK' as updated_table,
count(*) as rows_updated,
'Lower (Single row)' as maintenance_effort
from snow_dim_network
where network_id = 10
and network_director = 'Dr. Anand';

-- restore the original value after testing
update star_dim_hospital
set network_director = 'Dr. Ramesh'
where network_name = 'Apollo Healthcare Group'
and network_director = 'Dr. Anand';

-- restore the original value after testing
update snow_dim_network
set network_director = 'Dr. Ramesh'
where network_id = 10
and network_director = 'Dr. Anand';

-- task 14: full architecture record audit and schema comparison
select 'Star Schema' as schema_type,
'STAR_DIM_HOSPITAL' as table_name,count(*) as record_count
from star_dim_hospital
union all
select 'Star Schema' as schema_type,
'STAR_DIM_TREATMENT' as table_name,count(*) as record_count
from star_dim_treatment
union all
select 'Star Schema' as schema_type,
'STAR_FACT_CLAIMS' as table_name,count(*) as record_count
from star_fact_claims
union all
select 'Snowflake Schema' as schema_type,
'SNOW_DIM_NETWORK' as table_name,count(*) as record_count
from snow_dim_network
union all
select 'Snowflake Schema' as schema_type,
'SNOW_DIM_HOSPITAL' as table_name,count(*) as record_count
from snow_dim_hospital
union all
select 'Snowflake Schema' as schema_type,
'SNOW_DIM_DIAGNOSIS_GROUP' as table_name,
count(*) as record_count
from snow_dim_diagnosis_group
union all
select 'Snowflake Schema' as schema_type,
'SNOW_DIM_TREATMENT' as table_name,
count(*) as record_count
from snow_dim_treatment
union all
select 'Snowflake Schema' as schema_type,
'SNOW_FACT_CLAIMS' as table_name,
count(*) as record_count
from snow_fact_claims
order by schema_type,table_name;