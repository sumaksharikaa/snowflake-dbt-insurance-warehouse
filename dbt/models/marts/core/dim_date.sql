with days as (
    {{ date_spine(var('calendar_start'), var('calendar_end')) }}
)

select
    date_day,
    extract(year from date_day)                         as calendar_year,
    extract(quarter from date_day)                      as calendar_quarter,
    extract(month from date_day)                        as calendar_month,
    {{ month_start('date_day') }}                       as month_start,
    {{ quarter_start('date_day') }}                     as quarter_start,
    extract(dow from date_day) in (0, 6)                as is_weekend,
    date_day = cast({{ dbt.dateadd('day', -1, dbt.dateadd('month', 1, month_start('date_day'))) }} as date) as is_month_end
from days
