{#
  Project-local generic tests, so the project needs no external packages.
  Each test returns the failing rows; zero rows = pass.
#}

{% test not_negative(model, column_name) %}
    select {{ column_name }}
    from {{ model }}
    where {{ column_name }} < 0
{% endtest %}


{% test value_between(model, column_name, min_value, max_value) %}
    select {{ column_name }}
    from {{ model }}
    where {{ column_name }} < {{ min_value }} or {{ column_name }} > {{ max_value }}
{% endtest %}


{% test expression_is_true(model, column_name, expression) %}
    select *
    from {{ model }}
    where not coalesce(({{ expression }}), false)
{% endtest %}


{# Every combination of the given columns appears at most once. #}
{% test unique_combination(model, combination_of_columns) %}
    select {{ combination_of_columns | join(', ') }}, count(*) as n
    from {{ model }}
    group by {{ combination_of_columns | join(', ') }}
    having count(*) > 1
{% endtest %}
