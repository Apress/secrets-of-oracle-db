SELECT p.snap_id, s.snap_time, p.sql_id, p.hash_value, p.old_hash_value, p.plan_hash_value, p.cost
FROM stats$sql_plan_usage p, stats$snapshot s
WHERE p.snap_id=s.snap_id
AND p.hash_value=&hash_value_from_10g_sql_trace
ORDER BY p.snap_id;
