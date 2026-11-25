-- Paid loss triangle pivoted by development quarter, plus volume-weighted
-- age-to-age (link) factors: the inputs to a chain-ladder reserve estimate.
-- Compile with `dbt compile --select chain_ladder_factors` and run the SQL
-- from target/compiled in Snowflake or DuckDB.

with tri as (
    select * from {{ ref('mart_loss_triangle') }}
    where product_line = 'AUTO'
),

pivoted as (
    select
        accident_quarter,
        {% for d in range(8) %}
        max(case when development_quarter = {{ d }} then cumulative_paid end) as dev_{{ d }}{% if not loop.last %},{% endif %}
        {% endfor %}
    from tri
    group by accident_quarter
),

link_ratios as (
    select
        a.development_quarter as from_dev,
        sum(b.cumulative_paid) / nullif(sum(a.cumulative_paid), 0) as age_to_age_factor
    from tri as a
    inner join tri as b
        on b.accident_quarter = a.accident_quarter
       and b.development_quarter = a.development_quarter + 1
    group by a.development_quarter
)

select 'triangle' as section, cast(accident_quarter as varchar) as label,
       {% for d in range(8) %}round(dev_{{ d }}, 0) as dev_{{ d }}{% if not loop.last %}, {% endif %}{% endfor %}
from pivoted
union all
select 'link_ratio', cast(from_dev as varchar) || '->' || cast(from_dev + 1 as varchar),
       round(age_to_age_factor, 4){% for d in range(1, 8) %}, null{% endfor %}
from link_ratios
order by 1 desc, 2
