SELECT st.snap_id, to_char(sn.begin_interval_time,'dd. Mon yy hh24:mi') begin_time, 
st.plan_hash_value, st.optimizer_env_hash_value opt_env_hash, 
round(st.elapsed_time_delta/1000000,2) elapsed, 
round(st.cpu_time_delta/1000000,2) cpu,  
round(st.iowait_delta/1000000,2) iowait
FROM dba_hist_sqlstat st, dba_hist_snapshot sn
WHERE st.snap_id=sn.snap_id
AND st.sql_id='&sql_id'
ORDER BY st.snap_id;
