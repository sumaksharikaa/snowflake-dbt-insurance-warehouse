{#
  Small cross-database helpers. Each dispatches to an adapter-specific
  implementation, so the same models compile for Snowflake and for DuckDB.
#}

{# A contiguous series of dates [start_date, end_date] as a single column `date_day`. #}
{% macro date_spine(start_date, end_date) %}
    {{ return(adapter.dispatch('date_spine', 'insurance_warehouse')(start_date, end_date)) }}
{% endmacro %}

{% macro default__date_spine(start_date, end_date) %}
    select cast(range as date) as date_day
    from range(date '{{ start_date }}', date '{{ end_date }}' + interval 1 day, interval 1 day)
{% endmacro %}

{% macro snowflake__date_spine(start_date, end_date) %}
    select dateadd(day, row_number() over (order by seq4()) - 1, '{{ start_date }}'::date) as date_day
    from table(generator(rowcount => {{ (modules.datetime.date.fromisoformat(end_date) - modules.datetime.date.fromisoformat(start_date)).days + 1 }}))
{% endmacro %}


{# Money: always decimal(18,2) so sums don't drift and types match across adapters. #}
{% macro money(expr) -%}
    cast(round({{ expr }}, 2) as decimal(18, 2))
{%- endmacro %}


{# First day of the month / quarter as a DATE on every adapter. #}
{% macro month_start(expr) -%}
    cast(date_trunc('month', {{ expr }}) as date)
{%- endmacro %}

{% macro quarter_start(expr) -%}
    cast(date_trunc('quarter', {{ expr }}) as date)
{%- endmacro %}


{# Whole days between two dates (end - start). #}
{% macro days_between(start_date, end_date) -%}
    {{ dbt.datediff(start_date, end_date, 'day') }}
{%- endmacro %}


{# Stable surrogate key from one or more columns. #}
{% macro surrogate_key(columns) -%}
    md5(
        {%- for col in columns %}
        coalesce(cast({{ col }} as varchar), '~'){% if not loop.last %} || '|' ||{% endif %}
        {%- endfor %}
    )
{%- endmacro %}
