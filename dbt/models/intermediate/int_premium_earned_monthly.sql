{#
  Pro-rata (daily) earning of written premium.

  Each transaction's written premium is earned evenly over its exposure period,
  [txn_effective_date, term_expiration_date). A transaction contributes to a
  calendar month in proportion to the days the two overlap:

      earned(month) = written_premium * overlap_days / exposure_days

  A cancellation carries negative written premium over the remaining days, so
  it exactly offsets what the original transaction would have earned after
  the cancel date. Endorsements work the same way, positive or negative.

  Each month is rounded to cents and the final month of every transaction
  takes the rounding remainder ("plug"), so earned premium always adds back
  to written premium exactly. Rounding every row without a plug would drift.
#}
with txns as (
    select
        policy_txn_id,
        policy_id,
        product_line,
        txn_type,
        txn_effective_date as exposure_start,
        term_expiration_date as exposure_end,
        written_premium,
        {{ days_between('txn_effective_date', 'term_expiration_date') }} as exposure_days
    from {{ ref('stg_policy_transactions') }}
    where term_expiration_date > txn_effective_date
),

months as (
    select * from {{ ref('int_calendar_months') }}
),

exposure_overlap as (
    select
        txns.policy_txn_id,
        txns.policy_id,
        txns.product_line,
        txns.txn_type,
        months.month_start,
        txns.written_premium,
        txns.exposure_days,
        {{ days_between(
            'greatest(txns.exposure_start, months.month_start)',
            'least(txns.exposure_end, months.next_month_start)'
        ) }} as overlap_days
    from txns
    inner join months
        on months.month_start < txns.exposure_end
       and months.next_month_start > txns.exposure_start
),

rounded as (
    select
        *,
        round(written_premium * overlap_days / exposure_days, 2) as earned_rounded
    from exposure_overlap
    where overlap_days > 0
),

with_plug as (
    select
        *,
        row_number() over (partition by policy_txn_id order by month_start desc) as months_from_end,
        sum(earned_rounded) over (partition by policy_txn_id) as total_earned_rounded
    from rounded
)

select
    policy_txn_id,
    policy_id,
    product_line,
    txn_type,
    month_start,
    overlap_days,
    exposure_days,
    {{ money("case when months_from_end = 1
                   then earned_rounded + (written_premium - total_earned_rounded)
                   else earned_rounded end") }} as earned_premium
from with_plug
