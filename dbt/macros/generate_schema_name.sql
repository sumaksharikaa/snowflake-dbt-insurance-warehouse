{#
  Production (Snowflake) uses the configured schema names as-is: STAGING, CORE, FINANCE, CLAIMS.
  Every other target prefixes them with the target schema, so developers and
  CI runs never collide with production objects.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- elif target.name == 'snowflake' -%}
        {{ custom_schema_name | trim }}
    {%- else -%}
        {{ target.schema }}_{{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
