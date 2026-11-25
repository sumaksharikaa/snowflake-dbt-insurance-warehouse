-- Policy transactions are immutable events. Re-deliveries of the same
-- policy_txn_id are collapsed to one row.
select
    trim(policy_txn_id)                              as policy_txn_id,
    trim(policy_id)                                  as policy_id,
    trim(policy_number)                              as policy_number,
    trim(customer_id)                                as customer_id,
    trim(agent_id)                                   as agent_id,
    upper(trim(product_line))                        as product_line,
    upper(trim(risk_state))                          as risk_state,
    upper(trim(txn_type))                            as txn_type,
    try_cast(txn_effective_date as date)             as txn_effective_date,
    try_cast(term_effective_date as date)            as term_effective_date,
    try_cast(term_expiration_date as date)           as term_expiration_date,
    {{ money('try_cast(written_premium as decimal(18, 4))') }} as written_premium,
    try_cast(processed_at as timestamp)              as processed_at,
    _loaded_at
from {{ source('raw', 'policy_transactions') }}
qualify row_number() over (partition by trim(policy_txn_id) order by _loaded_at desc) = 1
