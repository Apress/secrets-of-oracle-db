-- configuration:
define snap_level=10
-- input: SID
accept sid prompt "Please enter SID (V$SESSION.SID): "
set null NULL
set verify off
set feedback off
col spid format 99999
col sid format 9999
col serial# format 99999
col machine format a10
col service_name format a16
col program format a11
col module format a10
col action format a10
col client_identifier format a17
set heading on


variable btime varchar2(30);
variable etime varchar2(30);
variable begin_snap number
variable end_snap number
variable ucomment varchar2(160)
variable date_format varchar2(30)
exec :date_format:='dd.Mon.yyyy hh24:mi:ss'
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
set termout off
-- due to DBMS_LOCK.SLEEP in capture.sql, idle wait event PL/SQL lock timer might appear in Top Timed Events section
-- this insert prevents it
INSERT INTO perfstat.stats$idle_event 
SELECT 'PL/SQL lock timer' FROM dual 
WHERE NOT EXISTS (SELECT event FROM perfstat.stats$idle_event WHERE event='PL/SQL lock timer');

begin
	:ucomment:=substr('SID-&sid' || '-&program' || '-&module' || '-&action' || '-&client_identifier',1,160);
	dbms_system.set_ev(&sid, &serial_nr, 10046, 12, '');
	-- Statspack
	:begin_snap:=statspack.snap(i_snap_level=> &snap_level, i_session_id=>&sid, i_ucomment=>:ucomment);
	-- convert to char since there are no date bind variables in SQL*Plus
	SELECT to_char(snap_time, :date_format) INTO :btime FROM stats$snapshot WHERE snap_id=:begin_snap;
end;
/
set termout on
set heading off
SELECT 'Begin snapshot: ' || :begin_snap FROM dual;
accept sleep_time prompt "Please enter snapshot interval in seconds (0 to take end snapshot immediately): "
exec dbms_lock.sleep(&sleep_time)
begin
	-- switch off SQL trace
	dbms_system.set_ev(&sid, &serial_nr, 10046, 0, '');
	-- Statspack
	:end_snap:=statspack.snap(i_snap_level=> &snap_level, i_session_id=>&sid, i_ucomment=>:ucomment);
	SELECT to_char(snap_time, :date_format) INTO :etime FROM stats$snapshot WHERE snap_id=:end_snap;
end;
/
SELECT 'End snapshot: ' || :end_snap FROM dual;
SELECT 'Begin time: ' || :btime || '; End time: '|| :etime || 
'; Duration (minutes): ' ||to_char( round((to_date(:etime, :date_format)-to_date(:btime, :date_format))* 86400/60,1) ) FROM dual;

