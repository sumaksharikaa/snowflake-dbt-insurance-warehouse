-- One row per policy, described by its most recent term.
with terms as (
    select * from {{ ref('int_policy_terms') }}
),

latest as (
    select *
    from terms
    qualify row_number() over (partition by policy_id order by term_effective_date desc) = 1
),

first_term as (
    select policy_id, min(term_effective_date) as original_inception_date, count(*) as term_count
    from terms
    group by policy_id
)

select
    latest.policy_id,
    latest.policy_number,
    latest.customer_id,
    latest.agent_id,
    latest.product_line,
    products.product_name,
    products.line_of_business,
    latest.risk_state,
    first_term.original_inception_date,
    first_term.term_count,
    latest.term_effective_date        as current_term_effective_date,
    latest.term_expiration_date       as current_term_expiration_date,
    latest.term_written_premium       as current_term_premium,
    latest.term_status                as policy_status,
    latest.cancellation_date
from latest
inner join first_term using (policy_id)
left join {{ ref('ref_product_lines') }} as products using (product_line)
