-- =====================================================================
-- 02  Raw landing tables, external stage and Snowpipe auto-ingest
-- Files land in s3://<bucket>/insurance/<table>/... and are loaded
-- automatically by event notifications (S3 -> SQS -> Snowpipe).
-- =====================================================================
use role accountadmin;

create storage integration if not exists s3_insurance_int
    type = external_stage
    storage_provider = 'S3'
    enabled = true
    storage_aws_role_arn = 'arn:aws:iam::<account-id>:role/snowflake-insurance-ingest'
    storage_allowed_locations = ('s3://<bucket>/insurance/');
grant usage on integration s3_insurance_int to role loader;

use role loader;
use schema insurance.raw;

create file format if not exists csv_with_header
    type = csv
    skip_header = 1
    field_optionally_enclosed_by = '"'
    empty_field_as_null = true
    null_if = ('')
    error_on_column_count_mismatch = true;

create stage if not exists insurance_stage
    storage_integration = s3_insurance_int
    url = 's3://<bucket>/insurance/'
    file_format = csv_with_header;

-- Raw tables keep every value as text (typing happens in dbt staging) plus load metadata.
create table if not exists claim_transactions (
    claim_txn_id varchar, claim_id varchar, txn_date varchar, txn_type varchar,
    amount varchar, processed_at varchar,
    _loaded_at timestamp_ltz default current_timestamp(),
    _source_file varchar
);

create table if not exists policy_transactions (
    policy_txn_id varchar, policy_id varchar, policy_number varchar, customer_id varchar,
    agent_id varchar, product_line varchar, risk_state varchar, txn_type varchar,
    txn_effective_date varchar, term_effective_date varchar, term_expiration_date varchar,
    written_premium varchar, processed_at varchar,
    _loaded_at timestamp_ltz default current_timestamp(),
    _source_file varchar
);
-- customers, agents, policy_coverages and claims follow the same pattern.

-- Snowpipe: COPY with a transformation that records the source file.
-- Snowpipe keeps 14 days of load history, so the same file is never loaded twice.
create pipe if not exists claim_transactions_pipe auto_ingest = true as
    copy into claim_transactions (
        claim_txn_id, claim_id, txn_date, txn_type, amount, processed_at, _source_file
    )
    from (
        select $1, $2, $3, $4, $5, $6, metadata$filename
        from @insurance_stage/claim_transactions/
    )
    on_error = 'skip_file';

create pipe if not exists policy_transactions_pipe auto_ingest = true as
    copy into policy_transactions (
        policy_txn_id, policy_id, policy_number, customer_id, agent_id, product_line, risk_state,
        txn_type, txn_effective_date, term_effective_date, term_expiration_date, written_premium,
        processed_at, _source_file
    )
    from (
        select $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, metadata$filename
        from @insurance_stage/policy_transactions/
    )
    on_error = 'skip_file';

-- The SQS ARN to configure as the S3 event notification target:
--   show pipes;  -> notification_channel
-- Monitoring:
--   select system$pipe_status('insurance.raw.claim_transactions_pipe');
--   select * from table(information_schema.copy_history(
--       table_name => 'CLAIM_TRANSACTIONS', start_time => dateadd(hour, -24, current_timestamp())));
