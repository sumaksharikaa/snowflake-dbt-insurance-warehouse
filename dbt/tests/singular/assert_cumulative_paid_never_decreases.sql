-- Cumulative paid losses in the triangle can only go down through recoveries,
-- and never below zero. A negative cumulative paid points to a sign error.
select *
from {{ ref('mart_loss_triangle') }}
where cumulative_paid < 0
