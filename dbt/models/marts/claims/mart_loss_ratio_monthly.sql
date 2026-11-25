-- Calendar-period loss ratio by product and month:
--   incurred losses booked in the month (paid + reserve change - recoveries)
--   divided by premium earned in the month.
-- Also shows the loss ratio without catastrophe losses, which is how
-- underlying profitability is usually judged.
with earned as (
    select product_line, month_start, sum(earned_premium) as earned_premium
    from {{ ref('fct_premium_monthly') }}
    where is_earned_to_date
    group by 1, 2
),

losses as (
    select
        txn.product_line,
        txn.accounting_month as month_start,
        sum(txn.net_paid_change)                                                       as paid_loss,
        sum(txn.incurred_change)                                                       as incurred_loss,
        sum(case when claims.is_catastrophe then txn.incurred_change else 0 end)       as cat_incurred_loss
    from {{ ref('fct_claim_transactions') }} as txn
    inner join {{ ref('fct_claims') }} as claims
        on claims.claim_id = txn.claim_id
    where txn.txn_date <= cast('{{ var("as_of_date") }}' as date)
    group by 1, 2
),

claim_counts as (
    select product_line, accident_month as month_start, count(*) as reported_claims
    from {{ ref('fct_claims') }}
    group by 1, 2
)

select
    earned.product_line,
    earned.month_start,
    {{ money('earned.earned_premium') }}                         as earned_premium,
    {{ money('coalesce(losses.paid_loss, 0)') }}                 as paid_loss,
    {{ money('coalesce(losses.incurred_loss, 0)') }}             as incurred_loss,
    {{ money('coalesce(losses.cat_incurred_loss, 0)') }}         as cat_incurred_loss,
    coalesce(claim_counts.reported_claims, 0)                   as new_claims,
    round(coalesce(losses.incurred_loss, 0) / nullif(earned.earned_premium, 0), 4) as loss_ratio,
    round((coalesce(losses.incurred_loss, 0) - coalesce(losses.cat_incurred_loss, 0))
          / nullif(earned.earned_premium, 0), 4)                as loss_ratio_ex_cat
from earned
left join losses
    on losses.product_line = earned.product_line
   and losses.month_start = earned.month_start
left join claim_counts
    on claim_counts.product_line = earned.product_line
   and claim_counts.month_start = earned.month_start
