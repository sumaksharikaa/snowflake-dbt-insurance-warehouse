select
    agent_id,
    agent_name,
    agency_name,
    state,
    region,
    commission_rate,
    hire_date
from {{ ref('stg_agents') }}
