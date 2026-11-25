{{ config(post_hook="{{ apply_pii_masking({'email': 'pii_email_mask', 'phone': 'pii_string_mask', 'date_of_birth': 'pii_date_mask'}) }}") }}

-- SCD Type 2 customer dimension built from the snapshot.
-- customer_sk identifies one version; customer_id identifies the person.
with versions as (
    select * from {{ ref('customers_snapshot') }}
)

select
    {{ surrogate_key(['customer_id', 'dbt_valid_from']) }}   as customer_sk,
    customer_id,
    first_name,
    last_name,
    email,
    phone,
    date_of_birth,
    city,
    state,
    zip_code,
    credit_tier,
    cast(dbt_valid_from as timestamp)                       as valid_from,
    cast(coalesce(dbt_valid_to, cast('9999-12-31' as timestamp)) as timestamp) as valid_to,
    dbt_valid_to is null                                    as is_current,
    row_number() over (partition by customer_id order by dbt_valid_from) as version_number
from versions
