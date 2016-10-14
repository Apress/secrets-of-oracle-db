set linesize 200
set trimout on
set trimspool on
set heading off
set pagesize 0
set feedback off
set heading off
spool disable.sql
select 'ALTER TABLE perfstat.' || table_name || ' DISABLE CONSTRAINT ' || constraint_name || ';' 
from dba_constraints 
where owner='PERFSTAT' and constraint_type='R';
prompt exit
exit
