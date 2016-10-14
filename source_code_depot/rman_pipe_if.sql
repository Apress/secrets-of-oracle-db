-- RCS Keywords: $Header: /cygdrive/c/home/ndebes/it/sql/RCS/rman_pipe_if.sql,v 1.2 2007/07/17 23:22:43 ndebes Exp ndebes $

GRANT create procedure to site_sys;
grant execute on dbms_pipe to site_sys;
grant execute on dbms_scheduler to site_sys;
grant execute on dbms_lob to site_sys;

create or replace package site_sys.rman_pipe_if authid current_user as
	-- send: return codes identical to DBMS_PIPE.SEND_MESSAGE: 0 on sucess
	function send(pipe_arg varchar2, -- same as argument to RMAN command line option PIPE
		msg varchar2) return number; -- message to send to RMAN via DBMS_PIPE, may contain several lines
	-- receive: return 0, when pipe empty, otherwise items (one or more lines) received
	function receive(pipe_arg varchar2, 
		msg out varchar2, -- message received from RMAN via DBMS_PIPE
		-- wait: 0: RMAN not ready for next command
		-- 1: RMAN ready for next command after RMAN sent RMAN-00572: waiting for dbms_pipe input
		wait_for_input out number, 
		rman_error out number, -- RMAN-nnnnn error from RMAN errorstack, 0 if no error
		rman_msg out varchar2, -- RMAN-nnnnn error message, NULL if no RMAN error
		ora_error out number, -- ORA-nnnnn error from RMAN errorstack, 0 if no error
		ora_msg out varchar2-- ORA-nnnnn error message, NULL if no ORA error
	) return number;
end;
/
show errors

create or replace package body site_sys.rman_pipe_if as
	/*
	pipe names used by RMAN, when run with rman PIPE pipe_arg:
	ORA$RMAN_<pipe_arg>_OUT
	ORA$RMAN_<pipe_arg>_IN
	*/
	function send(pipe_arg varchar2, msg varchar2) return number is
		-- length of name in v$db_pipes is 1000
		in_pipe varchar2(1000):='ORA$RMAN_' || pipe_arg || '_IN';
	begin
		dbms_pipe.pack_message(msg);
		return dbms_pipe.send_message(in_pipe, 1, 32768);
	end;

	-- unpacks pipe messages, maintains line counter, builds message to return to caller
	procedure next_item(item_type out number,
	   	line_no in out nocopy number,
		line out varchar2,
		msg in out nocopy varchar2)	
	is
		newline varchar2(1);
	begin
			-- next_item_type to ask for type of next item in message
			-- 9 is varchar
			item_type:=dbms_pipe.next_item_type;
			-- item_type 0 indicates no more items in message
			if item_type=0 then
				return;
			else
				line_no:=line_no+1;
				-- add a newline for lines >=2
				if line_no >=2 then
					newline:=chr(10);
				else
					newline:='';
				end if;
				dbms_pipe.unpack_message(line);
				-- append unpacked line to message
				msg:=msg || newline || line; 
			end if;
	end;

	function receive(pipe_arg varchar2, 
		msg out varchar2, 
		wait_for_input out number, 
		rman_error out number, 
		rman_msg out varchar2, 
		ora_error out number, 
		ora_msg out varchar2) return number 
	is
		out_pipe varchar2(1000):='ORA$RMAN_' || pipe_arg || '_OUT';
		item_type number;
		line_no number:=0;
		line varchar2(4000);
		rv number;
		pipe_empty exception;
		PRAGMA EXCEPTION_INIT(pipe_empty, -6556);
		colon_pos number;
	begin
		line_no :=0;
		msg:='';
		rman_error:=0;
		ora_error:=0;
		wait_for_input:=0;
		rv:=dbms_pipe.receive_message(out_pipe, 1);
		if rv > 0 then
			return 0;
		else
			loop
				-- next_item receives 4 (IN) OUT parameters
				next_item(item_type, line_no, line, msg);
				exit when item_type=0; -- item_type 0 indicates no more items in message
				/*
				look for RMAN error stack which always starts like this:
					RMAN-00571: ===========================================================
					RMAN-00569: =============== ERROR MESSAGE STACK FOLLOWS ===============
					RMAN-00571: ===========================================================
				success: no error stack; failure: error stack is present 
				*/
				-- look for RMAN-00572: waiting for dbms_pipe input
				if substr(line,1,10) = 'RMAN-00572' then
						wait_for_input:=1;
				end if;
				if substr(line,1,10) = 'RMAN-00569' then
					rman_error:=569;
					-- retrieve second RMAN-00571 line on error stack
					next_item(item_type, line_no, line, msg);
					-- retrieve first real error on error stack
					next_item(item_type, line_no, line, msg);
					if substr(line,1,5) = 'RMAN-' then
						colon_pos:=instr(line,':');
						if colon_pos > 0 then -- error code starts at 6, colon should be at position 11
							rman_error:=to_number(substr(line,6,colon_pos-6));
							rman_msg:=line;
						end if;
					end if;
				end if;
				-- look for ORA-nnnnn errors which might be on the error stack
				if rman_error > 0 and ora_error=0 then
					-- format is 'ORA-19566: message text' but could be 'ORA-1578: '
					if substr(line,1,4) = 'ORA-' then
						colon_pos:=instr(line,':');
						if colon_pos > 0 then -- error code starts at 5, colon should be at position 10
							ora_error:=to_number(substr(line,5,colon_pos-5));
							ora_msg:=line;
						end if;
					end if;
				end if;
			end loop;
			return line_no;
		end if;
	exception
		when pipe_empty then return 0;
	end;
end;
/
show errors

create or replace package site_sys.rman_backup authid current_user as
	procedure db_backup(job_name varchar2, pipe_arg varchar2, log_stream OUT clob);
end;
/
show errors

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
		for i in 1..10 LOOP
			rv:=site_sys.rman_pipe_if.receive(pipe_arg, msg, wait_for_input, rman_error, rman_msg, ora_error, ora_msg);
			log_msg:=i ||' ' || msg || line_break;
			dbms_output.put_line(log_msg);
			IF msg IS NOT NULL THEN
				dbms_lob.writeappend(log_stream, length(log_msg), log_msg);
			END IF;
			EXIT WHEN wait_for_input > 0;
		END LOOP;
		cmd:='BACKUP AS COMPRESSED BACKUPSET FORMAT "DB-%d-DBID-%I-%u" DATABASE;';
		log_msg:='Sending ' || cmd || line_break;
		dbms_output.put_line(log_msg);
		dbms_lob.writeappend(log_stream, length(log_msg), log_msg);
		rv:=site_sys.rman_pipe_if.send(pipe_arg, cmd);
		for i in 1..60 LOOP
			rv:=site_sys.rman_pipe_if.receive(pipe_arg, msg, wait_for_input, rman_error, rman_msg, ora_error, ora_msg);
			log_msg:=i ||' ' || msg || line_break;
			dbms_output.put_line(log_msg);
			IF msg IS NOT NULL THEN
				dbms_lob.writeappend(log_stream, length(log_msg), log_msg);
			END IF;
			EXIT WHEN wait_for_input > 0;
		END LOOP;
		cmd:='EXIT;';
		log_msg:='Sending ' || cmd || line_break;
		dbms_output.put_line(log_msg);
		dbms_lob.writeappend(log_stream, length(log_msg), log_msg);
		rv:=site_sys.rman_pipe_if.send(pipe_arg, cmd);
		for i in 1..10 LOOP
			rv:=site_sys.rman_pipe_if.receive(pipe_arg, msg, wait_for_input, rman_error, rman_msg, ora_error, ora_msg);
			log_msg:=i ||' ' || msg || line_break;
			dbms_output.put_line(log_msg);
			IF msg IS NOT NULL THEN
				dbms_lob.writeappend(log_stream, length(log_msg), log_msg);
			END IF;
			EXIT WHEN msg=rman_complete;
		END LOOP;
	end;
end;
/
show errors

set serveroutput on size 1000000

set long 1000000
set linesize 200
set pagesize 999
col log_stream format a190
VARIABLE log_stream CLOB
exec site_sys.rman_backup.db_backup(job_name=>'rman_job', pipe_arg=>'PIPELINE', log_stream=>:log_stream);
SELECT :log_stream FROM dual;

/*
variable rv number
exec :rv:=dbms_pipe.remove_pipe('&p')



create table site_sys.job_log (
OWNER VARCHAR2(30) NOT NULL, 
JOB_NAME                VARCHAR2(30)                   NOT NULL,
JOB_SUBNAME                                        VARCHAR2(30),
LOG_DATE                                           TIMESTAMP(6) WITH TIME ZONE,
log_stream	clob
);

-- cleanup, only if necessary
-- exec :rv:=dbms_pipe.remove_pipe('ORA$RMAN_PIPE_OUT')
-- exec :rv:=dbms_pipe.remove_pipe('ORA$RMAN_PIPE_IN')

variable pipe_arg varchar2(1000)
-- careful! must match strings passed to rman with PIPE=
-- if it doesn't match, communication with RMAN will not work
exec :pipe_arg:='PIPELINE';
variable rv number
variable msg varchar2(4000)
variable cmd varchar2(4000)
variable rman_error number
variable ora_error number
variable rman_msg varchar2(4000)
variable ora_msg varchar2(4000)
variable wait_for_input number
set null <NULL>

-- send command via pipe
begin
	:cmd:='list incarnation of database;';
	:cmd:='CONNECT CATALOG rman/rman@ten_tcp.world;';
	:cmd:='run {
		set maxcorrupt for datafile "F:\ORADATA\TEN\APPDATA01.DBF" to 10;
		backup format "c:\temp\DB-%d-%u.bkp" tablespace appdata;
		}';
	:cmd:='list copy of archivelog all;';
	:cmd:='show all;';
	:cmd:='BACKUP CURRENT CONTROLFILE;';
	:cmd:='exit;';
	-- send a message
	:rv:=site_sys.rman_pipe_if.send(:pipe_arg, :cmd);
end;
/
print rv

-- receive a message
exec :rv:=site_sys.rman_pipe_if.receive(:pipe_arg, :msg, :wait_for_input, :rman_error, :rman_msg, :ora_error, :ora_msg)
col msg format a70
col rv format 99
set linesize 130
col wait_for_input heading "Wait|for|input" format 99999
col rman_error heading "RMAN|Error" format 99999
col ora_error heading "ORA|Error" format 99999

-- fewer columns
SELECT :rv rv, :msg msg FROM dual;

SELECT :rman_error rman_error, :rman_msg rman_msg, :ora_error ora_error, :wait_for_input wait_for_input 
FROM dual;

-- just ora_msg
 
SELECT :rman_error rman_error, :rman_msg rman_msg, :ora_error ora_error, :ora_msg ora_msg, 
:wait_for_input wait_for_input 
FROM dual;

-- not needed
set serveroutput on
begin
	if :rman_error > 0 then
		dbms_output.put_line(:rman_msg);
	end if;
	if :ora_error > 0 then
		dbms_output.put_line(:ora_msg);
	end if;
end;
/

RMAN-00571: ===========================================================
RMAN-00569: =============== ERROR MESSAGE STACK FOLLOWS ===============
RMAN-00571: ===========================================================
RMAN-03009: failure of backup command on ORA_DISK_1 channel at 07/18/2007 17:01:59
ORA-19566: exceeded limit of 0 corrupt blocks for file F:\ORADATA\TEN\APPDATA01.DBF


*/
