-- =====================================================================
-- 04  Governance: PII masking, row-level security and tagging
--
-- Masking policies are attached by dbt post-hooks (macro apply_pii_masking)
-- every time the customer models are rebuilt, so protection is never lost
-- when a table is recreated.
-- =====================================================================
use role sysadmin;
use schema insurance.governance;

-- ------------------------------------------------------------ masking
create masking policy if not exists pii_string_mask as (val string) returns string ->
    case
        when is_role_in_session('PII_READER') then val
        when val is null then null
        else '***MASKED***'
    end;

create masking policy if not exists pii_email_mask as (val string) returns string ->
    case
        when is_role_in_session('PII_READER') then val
        when val is null then null
        else regexp_replace(val, '^[^@]+', '*****')        -- keeps the domain for analytics
    end;

create masking policy if not exists pii_date_mask as (val date) returns date ->
    case
        when is_role_in_session('PII_READER') then val
        when val is null then null
        else date_trunc('year', val)                        -- year of birth only
    end;

grant apply on masking policy pii_string_mask to role transformer;
grant apply on masking policy pii_email_mask  to role transformer;
grant apply on masking policy pii_date_mask   to role transformer;
grant usage on schema insurance.governance to role transformer;

-- ------------------------------------------------- row access by region
-- Regional underwriting managers see only their own states.
create table if not exists region_access_map (role_name varchar, state varchar);
insert into region_access_map values
    ('REPORTER_MIDWEST', 'WI'), ('REPORTER_MIDWEST', 'MN'), ('REPORTER_MIDWEST', 'IA'),
    ('REPORTER_MIDWEST', 'IL'), ('REPORTER_MIDWEST', 'MO'), ('REPORTER_MIDWEST', 'OH'),
    ('REPORTER_SOUTH', 'TX'), ('REPORTER_WEST', 'CO');

create row access policy if not exists state_row_access as (state_value varchar) returns boolean ->
    is_role_in_session('REPORTER')                          -- company-wide reporters see everything
    or exists (
        select 1 from insurance.governance.region_access_map m
        where is_role_in_session(m.role_name) and m.state = state_value
    );

grant apply on row access policy state_row_access to role transformer;

-- ------------------------------------------------------------ tagging
create tag if not exists data_classification allowed_values 'PII', 'CONFIDENTIAL', 'PUBLIC';
grant apply on tag data_classification to role transformer;

-- Audit who read PII (Enterprise edition):
--   select * from snowflake.account_usage.access_history
--   where array_contains('EMAIL'::variant, ...) order by query_start_time desc;
