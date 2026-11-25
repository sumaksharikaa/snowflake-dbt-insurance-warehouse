-- =====================================================================
-- 01  Warehouses, database, schemas and role-based access control
-- Run as a user with SYSADMIN + SECURITYADMIN (or ACCOUNTADMIN once).
-- =====================================================================

-- ---------------------------------------------------------------- roles
use role securityadmin;

create role if not exists loader      comment = 'Snowpipe / ingestion: writes RAW only';
create role if not exists transformer comment = 'dbt: reads RAW, owns STAGING..CLAIMS';
create role if not exists reporter    comment = 'BI and analysts: read marts, PII masked';
create role if not exists pii_reader  comment = 'Granted on top of REPORTER to see unmasked PII';

grant role loader      to role sysadmin;
grant role transformer to role sysadmin;
grant role reporter    to role sysadmin;
grant role pii_reader  to role sysadmin;

-- Service user for dbt with key-pair auth (no password).
create user if not exists dbt_svc
    default_role = transformer
    default_warehouse = transform_wh
    rsa_public_key = '<paste public key>'
    comment = 'dbt Core / CI service user';
grant role transformer to user dbt_svc;

-- ----------------------------------------------------------- warehouses
use role sysadmin;

create warehouse if not exists load_wh
    warehouse_size = xsmall auto_suspend = 60 auto_resume = true initially_suspended = true;
create warehouse if not exists transform_wh
    warehouse_size = small  auto_suspend = 60 auto_resume = true initially_suspended = true;
create warehouse if not exists reporting_wh
    warehouse_size = xsmall auto_suspend = 60 auto_resume = true initially_suspended = true
    min_cluster_count = 1 max_cluster_count = 3 scaling_policy = standard;   -- multi-cluster for BI concurrency

use role accountadmin;
create resource monitor if not exists insurance_monthly with
    credit_quota = 100 frequency = monthly start_timestamp = immediately
    triggers on 80 percent do notify
             on 100 percent do suspend;
alter warehouse transform_wh set resource_monitor = insurance_monthly;

-- Tasks (03_streams_and_tasks.sql) run as TRANSFORMER, including serverless tasks.
grant execute task, execute managed task on account to role transformer;
alter warehouse reporting_wh set resource_monitor = insurance_monthly;

-- ------------------------------------------------------ database objects
use role sysadmin;
create database if not exists insurance;
create schema if not exists insurance.raw;
create schema if not exists insurance.governance;
-- STAGING, INTERMEDIATE, CORE, FINANCE, CLAIMS, SNAPSHOTS, REFERENCE are created by dbt (owned by TRANSFORMER)

-- --------------------------------------------------------------- grants
use role securityadmin;

grant usage on warehouse load_wh      to role loader;
grant usage on warehouse transform_wh to role transformer;
grant usage on warehouse reporting_wh to role reporter;

grant usage on database insurance to role loader;
grant usage on database insurance to role transformer;
grant usage on database insurance to role reporter;

-- LOADER: write RAW only
grant usage, create table, create pipe, create stage on schema insurance.raw to role loader;
grant insert, select on future tables in schema insurance.raw to role loader;

-- TRANSFORMER: read RAW, create its own schemas
grant usage on schema insurance.raw to role transformer;
grant select on all tables in schema insurance.raw to role transformer;
grant select on future tables in schema insurance.raw to role transformer;
grant create schema on database insurance to role transformer;

-- REPORTER: read the marts (future grants keep working after every dbt run)
grant usage on future schemas in database insurance to role reporter;
grant select on future tables in schema insurance.core    to role reporter;
grant select on future tables in schema insurance.finance to role reporter;
grant select on future tables in schema insurance.claims  to role reporter;

grant role reporter to role pii_reader;
