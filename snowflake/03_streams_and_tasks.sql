-- =====================================================================
-- 03  Streams + Tasks: near-real-time large-loss alerting
--
-- dbt builds the warehouse in batch. Some events can't wait for the next
-- batch: a large payment or reserve change should reach the claims
-- leadership queue within minutes. An append-only stream on the raw table
-- captures new rows as Snowpipe lands them; a serverless task runs only when
-- the stream has data and moves large movements into an alert table.
-- =====================================================================
-- The table owner turns on change tracking once; streams read from it.
use role loader;
alter table insurance.raw.claim_transactions set change_tracking = true;

use role transformer;
create schema if not exists insurance.ops;
use schema insurance.ops;

create stream if not exists claim_transactions_stream
    on table insurance.raw.claim_transactions
    append_only = true
    comment = 'New claim financial transactions since the alert task last ran';

create table if not exists insurance.ops.large_loss_alerts (
    claim_txn_id   varchar,
    claim_id       varchar,
    txn_type       varchar,
    amount         number(18, 2),
    txn_date       date,
    alerted_at     timestamp_ltz default current_timestamp(),
    acknowledged   boolean default false
);

-- Serverless task: no warehouse to manage, billed per second of compute.
create or replace task large_loss_alert_task
    schedule = '5 minute'
    user_task_managed_initial_warehouse_size = 'XSMALL'
    when system$stream_has_data('insurance.ops.claim_transactions_stream')
as
    insert into insurance.ops.large_loss_alerts (claim_txn_id, claim_id, txn_type, amount, txn_date)
    select claim_txn_id, claim_id, txn_type, try_to_number(amount, 18, 2), try_to_date(txn_date)
    from insurance.ops.claim_transactions_stream
    where txn_type in ('PAYMENT', 'RESERVE')
      and abs(try_to_number(amount, 18, 2)) >= 25000;
    -- Consuming the stream in a DML statement advances its offset, so rows are processed once.

alter task large_loss_alert_task resume;

-- A second task, chained after the first, could notify via an email integration:
--   create task notify_task after large_loss_alert_task as
--     call system$send_email('claims_email_int', 'claims-leaders@example.com', 'Large loss alert', ...);

-- Observability
--   select * from table(information_schema.task_history(task_name => 'LARGE_LOSS_ALERT_TASK'))
--   order by scheduled_time desc limit 20;
