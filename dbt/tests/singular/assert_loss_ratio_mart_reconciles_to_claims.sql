-- Total incurred and paid in the loss-ratio mart must equal the claim-level
-- totals in fct_claims (both as of the valuation date). Returns a row only on mismatch.
with mart as (
    select sum(incurred_loss) as incurred, sum(paid_loss) as paid
    from {{ ref('mart_loss_ratio_monthly') }}
),

claims as (
    select sum(incurred_loss) as incurred, sum(paid_loss - recovered) as paid
    from {{ ref('fct_claims') }}
)

select mart.incurred as mart_incurred, claims.incurred as claims_incurred,
       mart.paid as mart_paid, claims.paid as claims_paid
from mart cross join claims
where abs(mart.incurred - claims.incurred) > 0.01
   or abs(mart.paid - claims.paid) > 0.01
