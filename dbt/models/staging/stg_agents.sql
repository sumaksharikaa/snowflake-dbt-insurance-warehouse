select
    trim(agent_id)                                   as agent_id,
    trim(agent_name)                                 as agent_name,
    trim(agency_name)                                as agency_name,
    upper(trim(state))                               as state,
    trim(region)                                     as region,
    cast(try_cast(commission_rate as decimal(5, 4)) as decimal(5, 4)) as commission_rate,
    try_cast(hire_date as date)                      as hire_date,
    try_cast(updated_at as timestamp)                as updated_at
from {{ source('raw', 'agents') }}
qualify row_number() over (partition by trim(agent_id) order by _loaded_at desc) = 1
