-- $Header: /cygdrive/c/home/ndebes/it/sql/awr_capture.sql,v 1.1 2007/11/03 14:43:49 ndebes Exp ndebes $
-- configuration:
define flush_level=ALL
-- sample idle events too
ALTER SYSTEM SET "_ash_sample_all"=TRUE SCOPE=MEMORY;
-- input: SID
accept sid prompt "Please enter SID (V$SESSION.SID): "
accept ucomment prompt "Please enter a comment (optional): "
set null NULL
set verify off
set feedback off
set heading on
col username format a10
col spid format 99999
col sid format 9999
col serial# format 99999
col machine format a10
col service_name format a16
col program format a11
col module format a10
col action format a10
col client_identifier format a17

variable begin_snap number
variable end_snap number
-- get spid and serial#
col spid new_value spid
col serial# new_value serial_nr
col program new_value program
col module new_value module
col action new_value action
col client_identifier new_value client_identifier
SELECT p.spid, s.sid, s.serial#, s.username, s.machine, s.service_name, s.program, 
	s.module, s.action, s.client_identifier
FROM v$session s, v$process p
WHERE s.paddr=p.addr
AND sid=&sid;
-- define
oradebug setospid &spid
-- level 3 errorstack dump contains open cursors for which PARSING IN may be missing in trace file
-- dbms_lock is in @?/rdbms/admin/dbmslock.sql and @?/rdbms/admin/prvtlock.plb
-- level 2 errorstack dump includes open cursors
oradebug dump errorstack 2
prompt Extended SQL trace file:
oradebug tracefile_name
begin
	dbms_system.set_ev(&sid, &serial_nr, 10046, 12, '');
	-- AWR
	:begin_snap:=dbms_workload_repository.create_snapshot(flush_level=> '&flush_level');
end;
/
set heading off
SELECT 'Begin snapshot: ' || :begin_snap FROM dual;
accept sleep_time prompt "Please enter snapshot interval in seconds (0 to take end snapshot immediately): "
exec dbms_lock.sleep(&sleep_time)
begin
	-- switch off SQL trace
	dbms_system.set_ev(&sid, &serial_nr, 10046, 0, '');
	-- AWR
	:end_snap:=dbms_workload_repository.create_snapshot(flush_level=> '&flush_level');
end;
/
SELECT 'End snapshot: ' || :end_snap FROM dual;
ALTER SYSTEM SET "_ash_sample_all"=FALSE SCOPE=MEMORY;

variable btime varchar2(30);
variable etime varchar2(30);
variable dbid number;
variable inst_num number;
variable date_format varchar2(30)
exec :date_format:='dd.Mon.yyyy hh24:mi:ss'
begin
	SELECT to_char(end_interval_time, :date_format), dbid, instance_number INTO :btime, :dbid, :inst_num
	FROM dba_hist_snapshot 
	WHERE snap_id=:begin_snap;

	SELECT to_char(end_interval_time, :date_format) INTO :etime
	FROM dba_hist_snapshot 
	WHERE snap_id=:end_snap;

end;
/
SELECT 'Begin time: ' || :btime || '; End time: '|| :etime || 
'; Duration (minutes): ' ||to_char( round((to_date(:etime, :date_format)-to_date(:btime, :date_format))* 86400/60,1) ) FROM dual;

set linesize 500
set trimout on
set trimspool on
set null ""
col spool_file new_value spool_file
set termout off
SELECT replace(nvl2('&ucomment','&ucomment.-','')||'SID-&sid.-SERIAL-&serial_nr.-ash.html', ' ') AS spool_file FROM dual;
spool &spool_file
SELECT * FROM TABLE (dbms_workload_repository.ash_report_html(:dbid, :inst_num, to_date(:btime, :date_format), to_date(:etime, :date_format), 0, 0, &sid, NULL, NULL, NULL, NULL, NULL, NULL));
spool off
set termout on
SELECT 'ASH Report file: &spool_file' FROM dual;
set termout off
SELECT replace(nvl2('&ucomment','&ucomment.-','')||'SID-&sid.-SERIAL-&serial_nr.-awr.html', ' ') AS spool_file FROM dual;
spool &spool_file
SELECT * FROM TABLE (dbms_workload_repository.awr_report_html(:dbid, :inst_num, :begin_snap, :end_snap, 8));
spool off
set termout on
SELECT 'AWR Report file: &spool_file' FROM dual;
