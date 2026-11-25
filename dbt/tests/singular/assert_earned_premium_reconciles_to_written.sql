-- Over the whole exposure period, earned premium must equal written premium
-- for every transaction, to the cent (the rounding plug guarantees it). Any
-- difference means a gap or overlap in the monthly earning logic.
with earned as (
    select policy_txn_id, sum(earned_premium) as earned
    from {{ ref('int_premium_earned_monthly') }}
    group by 1
)

select txn.policy_txn_id, txn.written_premium, earned.earned
from {{ ref('stg_policy_transactions') }} as txn
left join earned using (policy_txn_id)
where txn.term_expiration_date <= cast('{{ var("calendar_end") }}' as date)
  and txn.written_premium <> coalesce(earned.earned, 0)
