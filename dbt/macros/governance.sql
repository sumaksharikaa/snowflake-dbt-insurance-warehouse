{#
  Attach Snowflake masking policies to PII columns after a model is built.
  Used as a post-hook, so protection is re-applied every time dbt recreates
  the table. On any other adapter (DuckDB in dev/CI) it compiles to a no-op.

  Usage in a model config:
      post_hook="{{ apply_pii_masking({'email': 'pii_email_mask', 'phone': 'pii_string_mask'}) }}"
#}
{% macro apply_pii_masking(column_policies) %}
    {%- if target.type == 'snowflake' -%}
        {%- for column, policy in column_policies.items() %}
        alter {{ 'view' if model.config.materialized == 'view' else 'table' }} {{ this }}
            modify column {{ column }} set masking policy insurance.governance.{{ policy }};
        alter {{ 'view' if model.config.materialized == 'view' else 'table' }} {{ this }}
            modify column {{ column }} set tag insurance.governance.data_classification = 'PII';
        {%- endfor %}
    {%- else -%}
        select 1 /* masking policies apply on Snowflake only */
    {%- endif -%}
{% endmacro %}
