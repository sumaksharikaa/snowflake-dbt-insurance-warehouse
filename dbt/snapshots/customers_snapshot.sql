{#
  SCD Type 2 history of customers. Each run compares the latest customer
  extract with what is already stored, closes changed versions
  (dbt_valid_to) and inserts the new ones. The timestamp strategy uses the
  source's updated_at as the effective time of each change.
#}
{% snapshot customers_snapshot %}
    {{
        config(
            unique_key='customer_id',
            strategy='timestamp',
            updated_at='updated_at',
            invalidate_hard_deletes=False,
        )
    }}

    select
        customer_id, first_name, last_name, email, phone, date_of_birth,
        address_line1, city, state, zip_code, credit_tier, updated_at
    from {{ ref('stg_customers') }}

{% endsnapshot %}
