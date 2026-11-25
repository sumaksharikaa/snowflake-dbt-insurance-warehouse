-- Calendar months with their exclusive end date, used to earn premium.
with days as (
    {{ date_spine(var('calendar_start'), var('calendar_end')) }}
)

select
    date_day                                                    as month_start,
    cast({{ dbt.dateadd('month', 1, 'date_day') }} as date)     as next_month_start
from days
where extract(day from date_day) = 1
