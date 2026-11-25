{#
  Incremental: each run processes only rows loaded since the last run
  (by _loaded_at, the ingestion time), so late-arriving transactions are
  picked up whatever their business date. unique_key makes re-delivered rows
  update in place instead of duplicating: MERGE on Snowflake,
  delete+insert on DuckDB.
#}
{{
    config(
        materialized='incremental',
        unique_key='claim_txn_id',
        on_schema_change='append_new_columns',
    )
}}

with txns as (
    select * from {{ ref('stg_claim_transactions') }}
    {% if is_incremental() %}
    where _loaded_at > (select coalesce(max(_loaded_at), cast('1900-01-01' as timestamp)) from {{ this }})
    {% endif %}
)

select
    txns.claim_txn_id,
    txns.claim_id,
    claims.policy_id,
    policies.product_line,
    txns.txn_date,
    {{ month_start('txns.txn_date') }} as accounting_month,
    txns.txn_type,
    txns.amount,
    case txns.txn_type
        when 'PAYMENT'  then txns.amount
        when 'RECOVERY' then -txns.amount
        else 0
    end as net_paid_change,
    case txns.txn_type
        when 'PAYMENT'  then txns.amount
        when 'RESERVE'  then txns.amount
        when 'RECOVERY' then -txns.amount
        else 0
    end as incurred_change,
    txns.processed_at,
    txns._loaded_at
from txns
inner join {{ ref('stg_claims') }} as claims
    on claims.claim_id = txns.claim_id
left join {{ ref('dim_policy') }} as policies
    on policies.policy_id = claims.policy_id
