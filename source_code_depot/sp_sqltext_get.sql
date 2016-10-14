define hash_value=&1
set verify off
set long 100000
set trimout on
set trimspool on
set feedback off
set heading off
set linesize 32767
col sql_text format a32767
spool sp_sqltext_&hash_value..lst
select sql_text from table(site_sys.sp_sqltext(&hash_value));
spool off
exit
