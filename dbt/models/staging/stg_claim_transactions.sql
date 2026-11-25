-- Claim financial transactions. The source can re-deliver rows, so each
-- claim_txn_id is kept once (latest load wins).
--
-- Sign conventions used downstream:
--   RESERVE   change in case reserve (positive = increase, negative = take-down)
--   PAYMENT   loss paid (positive)
--   RECOVERY  salvage / subrogation received (positive, reduces net loss)
select
    trim(claim_txn_id)                               as claim_txn_id,
    trim(claim_id)                                   as claim_id,
    try_cast(txn_date as date)                       as txn_date,
    upper(trim(txn_type))                            as txn_type,
    {{ money('try_cast(amount as decimal(18, 4))') }} as amount,
    try_cast(processed_at as timestamp)              as processed_at,
    _loaded_at
from {{ source('raw', 'claim_transactions') }}
qualify row_number() over (partition by trim(claim_txn_id) order by _loaded_at desc) = 1
