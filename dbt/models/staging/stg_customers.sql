{{ config(post_hook="{{ apply_pii_masking({'email': 'pii_email_mask', 'phone': 'pii_string_mask', 'address_line1': 'pii_string_mask', 'date_of_birth': 'pii_date_mask'}) }}") }}

-- One row per customer: the latest version received. History is kept by the
-- customers snapshot (SCD Type 2), not here.
with source as (
    select * from {{ source('raw', 'customers') }}
)

select
    trim(customer_id)                          as customer_id,
    trim(first_name)                           as first_name,
    trim(last_name)                            as last_name,
    lower(trim(email))                         as email,
    trim(phone)                                as phone,
    try_cast(date_of_birth as date)            as date_of_birth,
    trim(address_line1)                        as address_line1,
    trim(city)                                 as city,
    upper(trim(state))                         as state,
    lpad(trim(zip_code), 5, '0')               as zip_code,
    upper(trim(credit_tier))                   as credit_tier,
    try_cast(updated_at as timestamp)          as updated_at,
    _loaded_at
from source
where customer_id is not null
qualify row_number() over (
    partition by trim(customer_id)
    order by try_cast(updated_at as timestamp) desc, _loaded_at desc
) = 1
