-- One row per policy term (a new term starts at NEW business or each RENEWAL),
-- with its full premium after endorsements and cancellations.
with txns as (
    select * from {{ ref('stg_policy_transactions') }}
),

terms as (
    select
        policy_id,
        term_effective_date,
        max(term_expiration_date)                                          as term_expiration_date,
        max(policy_number)                                                 as policy_number,
        max(customer_id)                                                   as customer_id,
        max(agent_id)                                                      as agent_id,
        max(product_line)                                                  as product_line,
        max(risk_state)                                                    as risk_state,
        max(case when txn_type in ('NEW', 'RENEWAL') then txn_type end)    as term_type,
        sum(case when txn_type in ('NEW', 'RENEWAL') then written_premium else 0 end) as original_term_premium,
        sum(written_premium)                                               as term_written_premium,
        sum(case when txn_type = 'ENDORSEMENT' then 1 else 0 end)          as endorsement_count,
        min(case when txn_type = 'CANCELLATION' then txn_effective_date end) as cancellation_date
    from txns
    group by policy_id, term_effective_date
)

select
    {{ surrogate_key(['policy_id', 'term_effective_date']) }}  as policy_term_id,
    terms.*,
    row_number() over (partition by policy_id order by term_effective_date) as term_number,
    case
        when cancellation_date is not null then 'CANCELLED'
        when term_expiration_date <= cast('{{ var("as_of_date") }}' as date) then 'EXPIRED'
        when term_effective_date > cast('{{ var("as_of_date") }}' as date) then 'FUTURE'
        else 'IN_FORCE'
    end as term_status,
    coalesce(cancellation_date, term_expiration_date) as coverage_end_date
from terms
