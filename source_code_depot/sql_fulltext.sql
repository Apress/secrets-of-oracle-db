-- pass old_hash_value as the single argument to the script
define old_hash_value='&1'
set verify off
set long 100000
set trimout on
set trimspool on
set feedback off
set heading off
-- more gives SP2-0267: linesize option 100000 out of range (1 through 32767)
set linesize 32767 
col sql_fulltext format a32767
spool sp_sqltext_&old_hash_value..lst
SELECT sql_fulltext FROM v$sql WHERE old_hash_value=&old_hash_value;
spool off
exit
