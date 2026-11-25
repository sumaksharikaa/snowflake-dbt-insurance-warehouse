-- Written premium at policy-transaction grain, with term and agent context.
select
    txn.policy_txn_id,
    terms.policy_term_id,
    txn.policy_id,
    txn.policy_number,
    txn.customer_id,
    txn.agent_id,
    txn.product_line,
    txn.risk_state,
    txn.txn_type,
    txn.txn_effective_date,
    {{ month_start('txn.txn_effective_date') }}        as accounting_month,
    txn.term_effective_date,
    txn.term_expiration_date,
    txn.written_premium,
    {{ money('txn.written_premium * agents.commission_rate') }} as commission_amount,
    txn.processed_at
from {{ ref('stg_policy_transactions') }} as txn
inner join {{ ref('int_policy_terms') }} as terms
    on terms.policy_id = txn.policy_id
   and terms.term_effective_date = txn.term_effective_date
left join {{ ref('stg_agents') }} as agents
    on agents.agent_id = txn.agent_id
