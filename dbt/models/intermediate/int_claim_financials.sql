-- Claim financials as of the valuation date.
--   case_reserve  = sum of reserve changes        (outstanding)
--   paid          = sum of payments
--   recovered     = sum of salvage/subrogation
--   incurred      = paid + case_reserve - recovered
with txns as (
    select * from {{ ref('stg_claim_transactions') }}
    where txn_date <= cast('{{ var("as_of_date") }}' as date)
)

select
    claim_id,
    {{ money("sum(case when txn_type = 'PAYMENT' then amount else 0 end)") }}  as paid_loss,
    {{ money("sum(case when txn_type = 'RECOVERY' then amount else 0 end)") }} as recovered,
    {{ money("sum(case when txn_type = 'RESERVE' then amount else 0 end)") }}  as case_reserve,
    {{ money("sum(case txn_type when 'PAYMENT' then amount when 'RESERVE' then amount when 'RECOVERY' then -amount else 0 end)") }} as incurred_loss,
    count(case when txn_type = 'PAYMENT' then 1 end) as payment_count,
    min(txn_date)                                    as first_txn_date,
    max(txn_date)                                    as last_txn_date
from txns
group by claim_id
