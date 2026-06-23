-- Backfill user_id on cotizaciones that have none.
-- Uses licitacion_assignment (assignee_id) — the correct table name.
-- Only fills where the licitación has exactly one assignee (unambiguous attribution).
UPDATE licitacion_cotizacion lc
SET user_id = la.assignee_id
FROM (
    SELECT licitacion_id, MAX(assignee_id) AS assignee_id
    FROM licitacion_assignment
    GROUP BY licitacion_id
    HAVING COUNT(*) = 1
) la
WHERE lc.licitacion_id = la.licitacion_id
  AND lc.user_id IS NULL;
