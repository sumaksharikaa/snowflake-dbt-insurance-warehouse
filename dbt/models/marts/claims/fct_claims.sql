-- Claim grain with financials as of the valuation date, the policy term that
-- covered the loss, and the customer version valid on the loss date (point-in-time
-- join to the SCD2 dimension).
with claims as (
    select * from {{ ref('stg_claims') }}
),

terms as (
    select * from {{ ref('int_policy_terms') }}
),

customers as (
    -- A customer's first recorded version also covers losses before it was captured.
    select
        customer_sk,
        customer_id,
        state as customer_state,
        credit_tier,
        case when version_number = 1 then cast('1900-01-01' as timestamp) else valid_from end as valid_from,
        valid_to
    from {{ ref('dim_customer') }}
)

select
    claims.claim_id,
    claims.policy_id,
    terms.policy_term_id,
    terms.product_line,
    terms.agent_id,
    terms.customer_id,
    customers.customer_sk,
    customers.customer_state,
    customers.credit_tier                                       as credit_tier_at_loss,
    claims.loss_date,
    {{ month_start('claims.loss_date') }}                       as accident_month,
    {{ quarter_start('claims.loss_date') }}                     as accident_quarter,
    extract(year from claims.loss_date)                         as accident_year,
    claims.reported_date,
    {{ days_between('claims.loss_date', 'claims.reported_date') }} as report_lag_days,
    claims.cause_of_loss,
    perils.peril_group,
    claims.catastrophe_code,
    claims.catastrophe_code is not null                         as is_catastrophe,
    claims.claim_status,
    claims.closed_date,
    coalesce(fin.paid_loss, 0)                                  as paid_loss,
    coalesce(fin.recovered, 0)                                  as recovered,
    coalesce(fin.case_reserve, 0)                               as case_reserve,
    coalesce(fin.incurred_loss, 0)                              as incurred_loss,
    coalesce(fin.payment_count, 0)                              as payment_count,
    claims.loss_date between terms.term_effective_date
        and {{ dbt.dateadd('day', -1, 'terms.coverage_end_date') }} as is_loss_in_coverage_period
from claims
left join terms
    on terms.policy_id = claims.policy_id
   and claims.loss_date >= terms.term_effective_date
   and claims.loss_date < terms.term_expiration_date
left join customers
    on customers.customer_id = terms.customer_id
   and cast(claims.loss_date as timestamp) >= customers.valid_from
   and cast(claims.loss_date as timestamp) < customers.valid_to
left join {{ ref('int_claim_financials') }} as fin
    on fin.claim_id = claims.claim_id
left join {{ ref('ref_causes_of_loss') }} as perils
    on perils.cause_of_loss = claims.cause_of_loss
