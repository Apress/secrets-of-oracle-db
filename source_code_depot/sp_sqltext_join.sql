set long 1000000
col module format a6
col snap_id format 9999999
col sql_text format a80 word_wrapped
SELECT s.snap_id, s.old_hash_value, 
	round(s.elapsed_time/s.executions/1000000, 2) ela_sec_per_exec, 
	floor(s.disk_reads/s.executions) read_per_exec, 
	floor(s.buffer_gets/s.executions) gets_per_exec, 
	s.module, t.sql_text
FROM stats$sql_summary s,
(SELECT hash_value, sql_text from table(site_sys.sp_sqltext())) t
WHERE s.old_hash_value=t.hash_value
AND s.elapsed_time/s.executions/1000000 > 1
ORDER BY s.elapsed_time, s.disk_reads, s.buffer_gets;
