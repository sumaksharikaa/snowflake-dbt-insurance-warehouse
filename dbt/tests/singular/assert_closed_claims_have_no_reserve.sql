-- A closed claim must have its case reserve fully taken down.
select claim_id, claim_status, case_reserve
from {{ ref('fct_claims') }}
where claim_status = 'CLOSED'
  and case_reserve <> 0
