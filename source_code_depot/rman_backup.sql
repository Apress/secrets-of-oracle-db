-- RCS Keywords: $Header: /cygdrive/c/home/ndebes/it/sql/RCS/rman_backup.sql,v 1.1 2007/12/23 12:05:22 ndebes Exp ndebes $

create or replace package site_sys.rman_backup authid current_user as
	procedure db_backup(job_name varchar2, pipe_arg varchar2, log_stream OUT clob);
end;
/
show errors

-- this is just a prototype. would use a subroutine for running a command and waiting for RMAN to signal readiness
-- for the next command
create or replace package body site_sys.rman_backup as
	procedure db_backup(job_name varchar2, pipe_arg varchar2, log_stream OUT clob)
	is
		rman_complete varchar2(30):='Recovery Manager complete.';
		cmd varchar2(4000);
		rv number;
		msg varchar2(4000);
		log_msg varchar2(4000);
		rman_error number;
		ora_error number;
		rman_msg varchar2(4000);
		ora_msg varchar2(4000);
		wait_for_input number;
		line_break varchar2(2):=chr(10);
		send_pipe varchar2(60);
		receive_pipe varchar2(60);
		i pls_integer:=1;
	begin
		dbms_lob.CREATETEMPORARY(lob_loc=>log_stream, cache=>true);
		-- purge the in and output pipe to remove any messages that may have remained after a failure
		-- careful! purge creates public pipes, if they do not exist! undocumented!
		-- RMAN files with RMAN-00578: pipe ORA$RMAN_PIPELINE_OUT is not private and owned by SYS, if public pipes exist
		-- Thus, to safely purge pipes, before RMAN starts, must create private pipes before purging
		send_pipe:='ORA$RMAN_' || pipe_arg || '_IN';
		receive_pipe:='ORA$RMAN_' || pipe_arg || '_OUT';
		-- create_pipe runs without error, if the pipes exist already
		rv:=dbms_pipe.create_pipe(pipename=>send_pipe, maxpipesize=>1024, private=>true);
		rv:=dbms_pipe.create_pipe(pipename=>receive_pipe, maxpipesize=>1024, private=>true);
		dbms_pipe.purge(send_pipe);
		dbms_pipe.purge(receive_pipe);
		-- start RMAN
		log_msg:='Starting RMAN with job ' || job_name || line_break;
		dbms_output.put_line(log_msg);
		dbms_lob.writeappend(log_stream, length(log_msg), log_msg);
		dbms_scheduler.run_job(job_name=>job_name,use_current_session=>false);
		-- before and after each command should verify that RMAN is still running
		-- e.g. this error causes RMAN to exit immediately: ORA-12705: Cannot access NLS data files or invalid environment specified
		LOOP
			rv:=site_sys.rman_pipe_if.receive(pipe_arg, msg, wait_for_input, rman_error, rman_msg, ora_error, ora_msg);
			log_msg:=i ||' ' || msg || line_break;
			i:=i+1;
			dbms_output.put_line(log_msg);
			IF msg IS NOT NULL THEN
				log_msg:=msg || line_break;
				dbms_lob.writeappend(log_stream, length(log_msg), log_msg);
			END IF;
			EXIT WHEN wait_for_input > 0;
		END LOOP;
		cmd:='BACKUP AS COMPRESSED BACKUPSET FORMAT "DB-%d-DBID-%I-%u" DATABASE;';
		log_msg:='Sending ' || cmd || line_break;
		dbms_output.put_line(log_msg);
		dbms_lob.writeappend(log_stream, length(log_msg), log_msg);
		rv:=site_sys.rman_pipe_if.send(pipe_arg, cmd);
		LOOP
			rv:=site_sys.rman_pipe_if.receive(pipe_arg, msg, wait_for_input, rman_error, rman_msg, ora_error, ora_msg);
			log_msg:=i ||' ' || msg || line_break;
			i:=i+1;
			dbms_output.put_line(log_msg);
			IF msg IS NOT NULL THEN
				log_msg:=msg || line_break;
				dbms_lob.writeappend(log_stream, length(log_msg), log_msg);
			END IF;
			EXIT WHEN wait_for_input > 0;
		END LOOP;
		cmd:='EXIT;';
		log_msg:='Sending ' || cmd || line_break;
		dbms_output.put_line(log_msg);
		dbms_lob.writeappend(log_stream, length(log_msg), log_msg);
		rv:=site_sys.rman_pipe_if.send(pipe_arg, cmd);
		LOOP
			rv:=site_sys.rman_pipe_if.receive(pipe_arg, msg, wait_for_input, rman_error, rman_msg, ora_error, ora_msg);
			log_msg:=i ||' ' || msg || line_break;
			i:=i+1;
			dbms_output.put_line(log_msg);
			IF msg IS NOT NULL THEN
				log_msg:=msg || line_break;
				dbms_lob.writeappend(log_stream, length(log_msg), log_msg);
			END IF;
			EXIT WHEN msg=rman_complete;
		END LOOP;
	end;
end;
/
show errors

set serveroutput on size 1000000

SET LONG 1000000
set linesize 200
set pagesize 999
col log_stream format a190
VARIABLE log_stream CLOB
EXECUTE site_sys.rman_backup.db_backup(job_name=>'rman_job', pipe_arg=>'PIPELINE', log_stream=>:log_stream);
SELECT :log_stream AS log_stream FROM dual;

/*

declare
	v_log_stream CLOB;
	v_log_stream_persistent CLOB;
	job_owner varchar2(30):='test'; 
	job_name varchar2(30):='test';
       	job_subname varchar2(30);
       	job_start timestamp with time zone:=systimestamp;
begin
	site_sys.rman_backup.db_backup(job_name=>'rman_job', pipe_arg=>'PIPELINE', log_stream=>v_log_stream);
	INSERT INTO site_sys.job_log(owner, job_name, job_subname, log_date, log_stream)
	VALUES(job_owner, job_name, job_subname, job_start, empty_clob())
	RETURNING log_stream INTO v_log_stream_persistent;
	dbms_lob.append(dest_lob=>v_log_stream_persistent, src_lob=>v_log_stream);
	commit;
end;
/

exec dbms_scheduler.drop_job('backup')

-- scheduler metadata variable job is undocumented
-- additional metadata in 11g?
-- log_date not set, when job is run manually
-- when the job completes DBA_SCHEDULER_JOBS.NEXT_RUN_DATE is copied into DBA_SCHEDULER_JOB_RUN_DETAILS.REQ_START_DATE
-- job_start scheduler metadata variable does not match dba_scheduler_job_log.LOG_DATE nor dba_scheduler_job_run_details.LOG_DATE
BEGIN
	DBMS_SCHEDULER.CREATE_JOB(
		job_name => 'backup',
		job_type => 'PLSQL_BLOCK',
		job_action => 'declare
	v_log_stream CLOB;
	v_log_stream_persistent CLOB;
	req_start_date TIMESTAMP(6) WITH TIME ZONE;
	v_job_name VARCHAR2(30);
begin
	v_job_name:=job_name;
	dbms_session.set_identifier(''JOB: ''||job); -- no effect on all_scheduler_job_log.client_id
	dbms_application_info.set_module(job_owner||''.''||job_name,null);
	SELECT next_run_date INTO req_start_date from all_scheduler_jobs where owner=job_owner AND job_name=v_job_name;
	site_sys.rman_backup.db_backup(job_name=>''rman_job'', pipe_arg=>''PIPELINE'', log_stream=>v_log_stream);
	INSERT INTO site_sys.job_log(job, owner, job_name, job_subname, req_start_date, log_stream)
	VALUES(job, job_owner, job_name, job_subname, req_start_date, empty_clob())
	RETURNING log_stream INTO v_log_stream_persistent;
	dbms_lob.append(dest_lob=>v_log_stream_persistent, src_lob=>v_log_stream);
	commit;
end;',
		start_date => SYSTIMESTAMP,
		-- repeat_interval => 'FREQ=DAILY;BYHOUR=22;BYMINUTE=30',
		repeat_interval => 'FREQ=MINUTELY;INTERVAL=3',
		enabled=>true /* default false! */
	);
END;
/
exec dbms_scheduler.run_job('backup')
exec dbms_scheduler.set_attribute('backup','repeat_interval','FREQ=DAILY;BYHOUR=4;BYMINUTE=15');
exec dbms_scheduler.enable('backup');
exec dbms_scheduler.disable('backup');

SELECT enabled, run_count, failure_count, last_start_date, next_run_date, systimestamp
FROM dba_scheduler_jobs 
WHERE job_name='BACKUP';

select SCHEDULER$_JOB

running jobs are apparently in X$JSKSLV
SELECT * FROM X$JSKSLV;

SQL> select object_id,object_type from dba_objects where object_name='BACKUP';

 OBJECT_ID OBJECT_TYPE
---------- -------------------
     13299 JOB

after dropping and recreating the job:
SQL> select object_id,object_type from dba_objects where object_name='BACKUP';

 OBJECT_ID OBJECT_TYPE
---------- -------------------
     13303 JOB



SELECT job, owner, job_name, req_start_date /*, log_stream */
FROM site_sys.job_log
WHERE job_name='BACKUP';


job really is OBJECT_ID from DBA_OBJECTS:
       JOB OWNER                          JOB_NAME
---------- ------------------------------ --------
TO_CHAR(LOG_DATE,'DD.MON.YYHH24:MI:SS
-------------------------------------
LOG_STREAM
--------------------------------------------------
     13303 SYS                            BACKUP


SELECT log_id, log_date, status, client_id
FROM dba_scheduler_job_log
WHERE job_name='BACKUP'
ORDER BY log_date;

SELECT log_id, req_start_date,owner, job_name, job_subname, status, error#, additional_info
FROM dba_scheduler_job_run_details
WHERE job_name='BACKUP'
ORDER BY log_date;


join:
SELECT log_id, d.req_start_date, status, log_stream
FROM dba_scheduler_job_run_details d,  site_sys.job_log l
WHERE d.owner='SYS' 
AND d.job_name='BACKUP'
AND d.owner=l.owner
AND d.job_name=l.job_name
AND d.req_start_date=l.req_start_date;

sample material:

before the job has started:
SQL> SELECT enabled, next_run_date, systimestamp
FROM dba_scheduler_jobs
WHERE job_name='BACKUP'
/
ENABLED NEXT_RUN_DATE                       SYSTIMESTAMP
------- ----------------------------------- -----------------------------------
TRUE    09-SEP-07 04.55.43.000000 AM +02:00 09-SEP-07 04.54.10.228961 AM +02:00

while the job is running:
DBB> SELECT username, client_identifier, module FROM v$session WHERE client_identifier like 'JOB%'
/
USERNAME CLIENT_IDENTIFIER MODULE
-------- ----------------- ----------
SYS      JOB: 13312        SYS.BACKUP

1 Row(s) processed.

DBB> SELECT owner, object_name, object_type, created FROM dba_objects WHERE object_id=13312
/
OWNER OBJECT_NAME OBJECT_TYPE CREATED
----- ----------- ----------- -------------------
SYS   BACKUP      JOB         09.09.2007 04:46:43

after job has completed:

SQL> SELECT log_id, d.req_start_date, status
FROM dba_scheduler_job_run_details d,  site_sys.job_log l
WHERE d.owner='SYS'
AND d.job_name='BACKUP'
AND d.owner=l.owner
AND d.job_name=l.job_name
AND d.req_start_date=l.req_start_date
ORDER BY log_id;
LOG_ID REQ_START_DATE                      STATUS
------ ----------------------------------- ---------
   831 09-SEP-07 04.26.21.600000 AM +02:00 SUCCEEDED
   833 09-SEP-07 04.29.21.600000 AM +02:00 SUCCEEDED
   835 09-SEP-07 04.32.21.000000 AM +02:00 SUCCEEDED
   837 09-SEP-07 04.35.21.000000 AM +02:00 SUCCEEDED
   839 09-SEP-07 04.38.21.000000 AM +02:00 SUCCEEDED
   841 09-SEP-07 04.41.21.000000 AM +02:00 SUCCEEDED
   846 09-SEP-07 04.46.43.800000 AM +02:00 SUCCEEDED
   850 09-SEP-07 04.49.43.800000 AM +02:00 SUCCEEDED
   850 09-SEP-07 04.49.43.800000 AM +02:00 SUCCEEDED
   854 09-SEP-07 04.52.43.000000 AM +02:00 SUCCEEDED
   854 09-SEP-07 04.52.43.000000 AM +02:00 SUCCEEDED
   856 09-SEP-07 04.55.43.000000 AM +02:00 SUCCEEDED


SQL> SELECT log_stream
FROM dba_scheduler_job_run_details d,  site_sys.job_log l
WHERE d.owner='SYS'
AND d.job_name='BACKUP'
AND d.log_id=856
AND d.owner=l.owner
AND d.job_name=l.job_name
AND d.req_start_date=l.req_start_date;

Starting RMAN with job rman_job
RMAN-06005: connected to target database: TEN (DBID=2863970444)
RMAN-00572: waiting for dbms_pipe input
Sending BACKUP AS COMPRESSED BACKUPSET FORMAT "DB-%d-DBID-%I-%u" DATABASE;
RMAN-03090: Starting backup at 09.Sep.07-04:55:45
RMAN-06009: using target database control file instead of recovery catalog
RMAN-08030: allocated channel: ORA_DISK_1
RMAN-08500: channel ORA_DISK_1: sid=135 devtype=DISK
RMAN-08046: channel ORA_DISK_1: starting compressed full datafile backupset
RMAN-08010: channel ORA_DISK_1: specifying datafile(s) in backupset
RMAN-08522: input datafile fno=00003 name=+DG/ten/datafile/sysaux.261.628550067
RMAN-08522: input datafile fno=00001 name=+DG/ten/datafile/system.259.628550039
RMAN-08522: input datafile fno=00004 name=+DG/ten/datafile/users.263.628550085
RMAN-08522: input datafile fno=00002 name=+DG/ten/datafile/undotbs1.260.628550065
RMAN-08038: channel ORA_DISK_1: starting piece 1 at 09.Sep.07-04:55:46
RMAN-08044: channel ORA_DISK_1: finished piece 1 at 09.Sep.07-04:56:11
RMAN-08530: piece handle=DB-TEN-DBID-2863970444-2pirfrqi tag=TAG20070909T045546 comment=NONE
RMAN-08540: channel ORA_DISK_1: backup set complete, elapsed time: 00:00:25
RMAN-08046: channel ORA_DISK_1: starting compressed full datafile backupset
RMAN-08010: channel ORA_DISK_1: specifying datafile(s) in backupset
RMAN-08011: including current control file in backupset
RMAN-08038: channel ORA_DISK_1: starting piece 1 at 09.Sep.07-04:56:12
RMAN-08044: channel ORA_DISK_1: finished piece 1 at 09.Sep.07-04:56:13
RMAN-08530: piece handle=/opt/oracle/product/db10.2/dbs/DB-TEN-DBID-2863970444-2qirfrrb tag=TAG20070909T045546 comment=NONE
RMAN-08540: channel ORA_DISK_1: backup set complete, elapsed time: 00:00:03
RMAN-03091: Finished backup at 09.Sep.07-04:56:14
RMAN-00572: waiting for dbms_pipe input
Sending EXIT;
Recovery Manager complete.


sample output:
SQL> SET LONG 1000000
SQL> VARIABLE log_stream CLOB
SQL> EXECUTE site_sys.rman_backup.db_backup(job_name=>'rman_job', pipe_arg=>'PIPELINE', log_stream=>:log_stream);
PL/SQL procedure successfully completed.
SQL> SELECT :log_stream AS log_stream FROM dual;

LOG_STREAM
---------------------------------------------------------------------------------------------------------------------------
Starting RMAN with job rman_job
RMAN-06005: connected to target database: TEN (DBID=2863970444)
RMAN-00572: waiting for dbms_pipe input
Sending BACKUP AS COMPRESSED BACKUPSET FORMAT "DB-%d-DBID-%I-%u" DATABASE;
RMAN-03090: Starting backup at 09.Sep.07-01:31:24
RMAN-06009: using target database control file instead of recovery catalog
RMAN-08030: allocated channel: ORA_DISK_1
RMAN-08500: channel ORA_DISK_1: sid=159 devtype=DISK
RMAN-08046: channel ORA_DISK_1: starting compressed full datafile backupset
RMAN-08010: channel ORA_DISK_1: specifying datafile(s) in backupset
RMAN-08522: input datafile fno=00003 name=+DG/ten/datafile/sysaux.261.628550067
RMAN-08522: input datafile fno=00001 name=+DG/ten/datafile/system.259.628550039
RMAN-08522: input datafile fno=00004 name=+DG/ten/datafile/users.263.628550085
RMAN-08522: input datafile fno=00002 name=+DG/ten/datafile/undotbs1.260.628550065
RMAN-08038: channel ORA_DISK_1: starting piece 1 at 09.Sep.07-01:31:25
RMAN-08044: channel ORA_DISK_1: finished piece 1 at 09.Sep.07-01:31:50
RMAN-08530: piece handle=/opt/oracle/product/db10.2/dbs/DB-TEN-DBID-2863970444-0tirffrd tag=TAG20070909T013125 comment=NONE
RMAN-08540: channel ORA_DISK_1: backup set complete, elapsed time: 00:00:25
RMAN-08046: channel ORA_DISK_1: starting compressed full datafile backupset
RMAN-08010: channel ORA_DISK_1: specifying datafile(s) in backupset
RMAN-08011: including current control file in backupset
RMAN-08038: channel ORA_DISK_1: starting piece 1 at 09.Sep.07-01:31:53
RMAN-08044: channel ORA_DISK_1: finished piece 1 at 09.Sep.07-01:31:54
RMAN-08530: piece handle=/opt/oracle/product/db10.2/dbs/DB-TEN-DBID-2863970444-0uirffs7 tag=TAG20070909T013125 comment=NONE
RMAN-08540: channel ORA_DISK_1: backup set complete, elapsed time: 00:00:03
RMAN-03091: Finished backup at 09.Sep.07-01:31:54
RMAN-00572: waiting for dbms_pipe input
Sending EXIT;
Recovery Manager complete.

variable rv number
exec :rv:=dbms_pipe.remove_pipe('&p')



drop table site_sys.job_log;
create table site_sys.job_log (
job NUMBER,
owner VARCHAR2(30) NOT NULL, 
JOB_NAME                VARCHAR2(30)                   NOT NULL,
JOB_SUBNAME                                        VARCHAR2(30),
req_start_date                                           TIMESTAMP(6) WITH TIME ZONE,
log_stream	clob
);

*/
