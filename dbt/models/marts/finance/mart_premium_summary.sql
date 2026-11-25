-- Product x month premium summary with cumulative written/earned and the
-- unearned premium reserve (UPR) at each month end.
with monthly as (
    select
        product_line,
        month_start,
        sum(written_premium) as written_premium,
        sum(earned_premium)  as earned_premium
    from {{ ref('fct_premium_monthly') }}
    where is_earned_to_date
    group by 1, 2
),

policies_in_force as (
    select
        terms.product_line,
        months.month_start,
        count(distinct terms.policy_id) as policies_in_force
    from {{ ref('int_policy_terms') }} as terms
    inner join {{ ref('int_calendar_months') }} as months
        on months.month_start >= terms.term_effective_date
       and months.month_start < terms.coverage_end_date
    group by 1, 2
)

select
    monthly.product_line,
    monthly.month_start,
    {{ money('monthly.written_premium') }} as written_premium,
    {{ money('monthly.earned_premium') }}  as earned_premium,
    {{ money('sum(monthly.written_premium) over (partition by monthly.product_line order by monthly.month_start
             rows between unbounded preceding and current row)') }} as cumulative_written,
    {{ money('sum(monthly.earned_premium) over (partition by monthly.product_line order by monthly.month_start
             rows between unbounded preceding and current row)') }} as cumulative_earned,
    {{ money('sum(monthly.written_premium - monthly.earned_premium) over (
             partition by monthly.product_line order by monthly.month_start
             rows between unbounded preceding and current row)') }} as unearned_premium_reserve,
    coalesce(pif.policies_in_force, 0) as policies_in_force
from monthly
left join policies_in_force as pif
    on pif.product_line = monthly.product_line
   and pif.month_start = monthly.month_start
