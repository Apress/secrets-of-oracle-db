define installation_schema='SITE_SYS'
define tablespace_name='tools'

create user &installation_schema identified by secret default tablespace &tablespace_name 
quota 100m on &tablespace_name;

alter user &installation_schema password expire account lock;

execute DBMS_STATS.CREATE_STAT_TABLE ('&installation_schema','system_stats');


variable statid varchar2(30)
variable statown varchar2(30)
variable stattab varchar2(30)
variable iterations number
-- collection interval in minutes
variable interval number 
set autoprint on
exec :statown:='&installation_schema';
exec :stattab:='system_stats'
exec :iterations:=4
exec :interval:=15

begin
	FOR i in 1 .. :iterations LOOP
		:statid := to_char(sysdate, '"sysstat_"ddmonyy_hh24"h"mi');
		DBMS_STATS.GATHER_SYSTEM_STATS (
			gathering_mode =>'start',
			stattab => 'system_stats',
			statid => :statid,
			statown => :statown
		);
		dbms_lock.sleep(:interval * 60);
		DBMS_STATS.GATHER_SYSTEM_STATS (
			gathering_mode =>'stop',
			stattab => :stattab,
			statid => :statid,
			statown => :statown
		);
	END LOOP;
end;
/

column statid format a20
column c1 format a13 
column c2 format a16 
column c3 format a16 
select STATID, C1, C2, C3 from &installation_schema..system_stats; 

SET SERVEROUTPUT ON
DECLARE
  STATUS VARCHAR2(20);
  start_time DATE;
  stop_time DATE;
  PVALUE NUMBER;
  PNAME VARCHAR2(30);
statown varchar2(30):=:statown;
stattab varchar2(30):=:stattab;
	TYPE stat_name_list_t IS TABLE OF VARCHAR2(30) INDEX BY BINARY_INTEGER;
        stat_name_list stat_name_list_t;
        i binary_integer:=1;
BEGIN
stat_name_list(i):='iotfrspeed';i:=i+1;
stat_name_list(i):='ioseektim';i:=i+1;
stat_name_list(i):='sreadtim';i:=i+1;
stat_name_list(i):='mreadtim';i:=i+1;
stat_name_list(i):='cpuspeed';i:=i+1;
stat_name_list(i):='cpuspeednw';i:=i+1;
stat_name_list(i):='mbrc';i:=i+1;
stat_name_list(i):='maxthr';i:=i+1;
stat_name_list(i):='slavethr';i:=i+1;
for j in 1..stat_name_list.count loop
	DBMS_STATS.GET_SYSTEM_STATS(status, start_time, stop_time, stat_name_list(j), pvalue, stattab => stattab,
        statid => :statid, statown => statown);
	if j=1 then
		DBMS_OUTPUT.PUT_LINE('status: '||status);
		DBMS_OUTPUT.PUT_LINE('start: '||start_time);
		DBMS_OUTPUT.PUT_LINE('stop: '||stop_time);
	end if;
	DBMS_OUTPUT.PUT_LINE(stat_name_list(j) || ': ' || pvalue);
end loop;	
END;
/

set doc off
/*

$ psrinfo -p -v
The UltraSPARC-III physical processor has 1 virtual processor (0)
The UltraSPARC-III physical processor has 1 virtual processor (1)
$ psrinfo  -v
Status of virtual processor 0 as of: 09/17/2007 17:19:10
  on-line since 07/24/2007 14:24:25.
  The sparcv9 processor operates at 750 MHz,
        and has a sparcv9 floating point processor.
Status of virtual processor 1 as of: 09/17/2007 17:19:10
  on-line since 07/24/2007 14:24:26.
  The sparcv9 processor operates at 750 MHz,
        and has a sparcv9 floating point processor.

machine was idle:

status: COMPLETED
start: 12.09.07 14:27
stop: 12.09.07 14:27
iotfrspeed: 4096
ioseektim: 10
sreadtim:
mreadtim:
cpuspeed:
cpuspeednw: 364.320426399122
mbrc:
maxthr:
slavethr:

ran exp and parallel degree 2 select:
status: COMPLETED
start: 17.09.07 17:23
stop: 17.09.07 17:28
iotfrspeed:
ioseektim:
sreadtim: 10.201
mreadtim: 2.473
cpuspeed: 369
cpuspeednw:
mbrc: 16
maxthr: 1688576
slavethr: 23552

*/
