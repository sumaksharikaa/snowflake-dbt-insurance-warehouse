-- Claim headers arrive as a new version on each status change; keep the latest.
select
    trim(claim_id)                                   as claim_id,
    trim(policy_id)                                  as policy_id,
    try_cast(loss_date as date)                      as loss_date,
    try_cast(reported_date as date)                  as reported_date,
    upper(trim(cause_of_loss))                       as cause_of_loss,
    nullif(trim(catastrophe_code), '')               as catastrophe_code,
    upper(trim(claim_status))                        as claim_status,
    try_cast(nullif(trim(closed_date), '') as date)  as closed_date,
    try_cast(updated_at as timestamp)                as updated_at
from {{ source('raw', 'claims') }}
qualify row_number() over (
    partition by trim(claim_id)
    order by try_cast(updated_at as timestamp) desc, _loaded_at desc
) = 1
