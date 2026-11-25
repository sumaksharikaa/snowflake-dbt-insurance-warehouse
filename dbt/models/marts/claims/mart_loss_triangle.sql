{#
  Loss development triangle: cumulative paid and incurred losses by accident
  quarter (rows) and development quarter (columns: 0 = the quarter of loss).
  Every cell up to the valuation date is present, even with no activity, so
  cumulative values carry forward. Actuaries use the age-to-age factors to
  project ultimate losses (chain ladder).
#}
with claims as (
    select claim_id, product_line, accident_quarter from {{ ref('fct_claims') }}
),

txns as (
    select
        claims.product_line,
        claims.accident_quarter,
        {{ dbt.datediff('claims.accident_quarter', quarter_start('txn.txn_date'), 'quarter') }} as development_quarter,
        txn.net_paid_change,
        txn.incurred_change
    from {{ ref('fct_claim_transactions') }} as txn
    inner join claims on claims.claim_id = txn.claim_id
    where txn.txn_date <= cast('{{ var("as_of_date") }}' as date)
),

cells as (
    -- every (product, accident quarter, development quarter) up to the valuation date
    select distinct
        claims.product_line,
        claims.accident_quarter,
        dev.development_quarter
    from claims
    cross join (
        select row_number() over (order by month_start) - 1 as development_quarter
        from {{ ref('int_calendar_months') }}
    ) as dev
    where cast({{ dbt.dateadd('quarter', 'dev.development_quarter', 'claims.accident_quarter') }} as date)
          <= cast('{{ var("as_of_date") }}' as date)
),

activity as (
    select product_line, accident_quarter, development_quarter,
           sum(net_paid_change) as paid, sum(incurred_change) as incurred
    from txns
    group by 1, 2, 3
)

select
    cells.product_line,
    cells.accident_quarter,
    cells.development_quarter,
    {{ money('coalesce(activity.paid, 0)') }}     as incremental_paid,
    {{ money('coalesce(activity.incurred, 0)') }} as incremental_incurred,
    {{ money('sum(coalesce(activity.paid, 0)) over (
        partition by cells.product_line, cells.accident_quarter
        order by cells.development_quarter rows between unbounded preceding and current row)') }} as cumulative_paid,
    {{ money('sum(coalesce(activity.incurred, 0)) over (
        partition by cells.product_line, cells.accident_quarter
        order by cells.development_quarter rows between unbounded preceding and current row)') }} as cumulative_incurred
from cells
left join activity
    on activity.product_line = cells.product_line
   and activity.accident_quarter = cells.accident_quarter
   and activity.development_quarter = cells.development_quarter
