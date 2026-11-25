select
    trim(policy_id)                                  as policy_id,
    try_cast(term_effective_date as date)            as term_effective_date,
    upper(trim(coverage_code))                       as coverage_code,
    try_cast(limit_amount as decimal(18, 2))         as limit_amount,
    try_cast(deductible as decimal(18, 2))           as deductible,
    {{ money('try_cast(coverage_premium as decimal(18, 4))') }} as coverage_premium
from {{ source('raw', 'policy_coverages') }}
qualify row_number() over (
    partition by trim(policy_id), term_effective_date, upper(trim(coverage_code))
    order by _loaded_at desc
) = 1
