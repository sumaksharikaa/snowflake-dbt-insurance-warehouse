-- Policy x month: written premium (booked in the transaction's effective month)
-- and earned premium (pro-rata by day). Months after the valuation date carry
-- the unearned premium that will earn later.
with written as (
    select
        policy_id,
        product_line,
        {{ month_start('txn_effective_date') }} as month_start,
        sum(written_premium) as written_premium
    from {{ ref('stg_policy_transactions') }}
    group by 1, 2, 3
),

earned as (
    select
        policy_id,
        product_line,
        month_start,
        sum(earned_premium) as earned_premium
    from {{ ref('int_premium_earned_monthly') }}
    group by 1, 2, 3
),

combined as (
    select
        coalesce(w.policy_id, e.policy_id)        as policy_id,
        coalesce(w.product_line, e.product_line)  as product_line,
        coalesce(w.month_start, e.month_start)    as month_start,
        coalesce(w.written_premium, 0)            as written_premium,
        coalesce(e.earned_premium, 0)             as earned_premium
    from written as w
    full outer join earned as e
        on e.policy_id = w.policy_id
       and e.month_start = w.month_start
)

select
    {{ surrogate_key(['policy_id', 'month_start']) }} as policy_month_id,
    policy_id,
    product_line,
    month_start,
    {{ money('written_premium') }} as written_premium,
    {{ money('earned_premium') }}  as earned_premium,
    month_start <= cast('{{ var("as_of_date") }}' as date) as is_earned_to_date
from combined
