Rem
Rem $Header: sprepins.sql 31-may-2005.16:31:36 cdgreen Exp $
Rem
Rem sprepins.sql
Rem
Rem Copyright (c) 2001, 2005, Oracle. All rights reserved.  
Rem
Rem    NAME
Rem      sprepins.sql - StatsPack Report Instance
Rem
Rem    DESCRIPTION
Rem      SQL*Plus command file to report on differences between
Rem      values recorded in two snapshots.
Rem
Rem      This script requests the user for the dbid and instance number
Rem      of the instance to report on, before producing the standard
Rem      Statspack report.
Rem
Rem    NOTES
Rem      Usually run as the STATSPACK owner, PERFSTAT
Rem
Rem    MODIFIED   (MM/DD/YY)
Rem    cdgreen     05/23/05 - 4246955
Rem    cdgreen     02/28/05 - 10gR2 misc
Rem    vbarrier    02/18/05 - 4081984/4071648
Rem    cdgreen     10/29/04 - 10gR2_sqlstats
Rem    cdgreen     10/25/04 - 3970898
Rem    vbarrier    09/03/04 - Wait Event Histogram
Rem    cdgreen     07/15/04 - sp_10_r2
Rem    cdialeri    03/30/04 - 3356242
Rem    vbarrier    03/18/04 - 3517841
Rem    vbarrier    02/12/04 - 3412853/3378066
Rem    vbarrier    01/30/04 - 3411063/3411129
Rem    cdialeri    12/03/03 - 3290482
Rem    cdialeri    10/14/03 - 10g - streams - rvenkate 
Rem    cdialeri    08/06/03 - 10g F3 
Rem    vbarrier    02/25/03 - 10g RAC
Rem    cdialeri    11/15/02 - 10g R1
Rem    cdialeri    10/29/02 - 2648471
Rem    cdialeri    09/26/02 - 10.0
Rem    vbarrier    07/14/02 - Segment Statistics: outerjoin + order by
Rem    vbarrier    07/10/02 - Input checking + capt/tot SQL + snapdays
Rem    vbarrier    03/20/02 - Module in SQL reporting + 2188360
Rem    vbarrier    03/05/02 - Segment Statistics
Rem    spommere    02/14/02 - cleanup RAC stats that are no longer needed
Rem    spommere    02/08/02 - 2212357
Rem    cdialeri    02/07/02 - 2218573
Rem    cdialeri    01/30/02 - 2184717
Rem    cdialeri    01/09/02 - 9.2 - features 2
Rem    ykunitom    12/21/01 - 1396578: fixed '% Non-Parse CPU'
Rem    cdialeri    12/19/01 - 9.2 - features 1
Rem    cdialeri    09/20/01 - 1767338,1910458,1774694
Rem    cdialeri    04/26/01 - Renamed from spreport.sql
Rem    cdialeri    03/02/01 - 9.0
Rem    cdialeri    09/12/00 - sp_1404195
Rem    cdialeri    07/10/00 - 1349995
Rem    cdialeri    06/21/00 - 1336259
Rem    cdialeri    04/06/00 - 1261813
Rem    cdialeri    03/28/00 - sp_purge
Rem    cdialeri    02/16/00 - 1191805
Rem    cdialeri    11/01/99 - Enhance, 1059172
Rem    cgervasi    06/16/98 - Remove references to wrqs
Rem    cmlim       07/30/97 - Modified system events
Rem    gwood.uk    02/30/94 - Modified
Rem    densor.uk   03/31/93 - Modified
Rem    cellis.uk   11/15/89 - Created
Rem


-- 
-- Get the report settings
@@sprepcon.sql

--
--

clear break compute;
repfooter off;
ttitle off;
btitle off;
set timing off veri off space 1 flush on pause off termout on numwidth 10;
set echo off feedback off pagesize 60 newpage 1 recsep off;
set trimspool on trimout on define "&" concat "." serveroutput on;
set linesize &&linesize_fmt;
--
--  Must not be modified
--  Bytes to megabytes
define btomb = 1048576;
--  Bytes to kilobytes
define btokb = 1024;
--  Centiseconds to seconds
define cstos = 100;
--  Microseconds to milli-seconds
define ustoms = 1000;
--  Microseconds to seconds
define ustos = 1000000;
define top_n_events = 5;
define total_event_time_s_th = .001;
define pct_cpu_diff_th = 5;

--
-- Request the DB Id and Instance Number, if they are not specified

column instt_num  heading "Inst Num"  format 99999;
column instt_name heading "Instance"  format a12;
column dbb_name   heading "DB Name"   format a12;
column dbbid      heading "DB Id"     format 9999999999 just c;
column host       heading "Host"      format a12;

prompt
prompt
prompt Instances in this Statspack schema
prompt ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
select distinct 
       dbid            dbbid
     , instance_number instt_num
     , db_name         dbb_name
     , instance_name   instt_name
     , host_name       host
  from stats$database_instance;

prompt
prompt Using &&dbid for database Id
prompt Using &&inst_num for instance number


--
--  Set up the binds for dbid and instance_number

variable dbid       number;
variable inst_num   number;
begin
  :dbid      :=  &dbid;
  :inst_num  :=  &inst_num;
end;
/


--
--  Error reporting

whenever sqlerror exit;
variable max_snap_time char(10);
declare

  cursor cidnum is
     select 'X'
       from stats$database_instance
      where instance_number = :inst_num
        and dbid            = :dbid;

  cursor csnapid is
     select to_char(max(snap_time),'dd/mm/yyyy')
       from stats$snapshot
      where instance_number = :inst_num
        and dbid            = :dbid;

  vx     char(1);

begin

  -- Check Database Id/Instance Number is a valid pair
  open cidnum;
  fetch cidnum into vx;
  if cidnum%notfound then
    raise_application_error(-20200,
      'Database/Instance '||:dbid||'/'||:inst_num||' does not exist in STATS$DATABASE_INSTANCE');
  end if;
  close cidnum;

  -- Check Snapshots exist for Database Id/Instance Number
  open csnapid;
  fetch csnapid into :max_snap_time;
  if csnapid%notfound then
    raise_application_error(-20200,
      'No snapshots exist for Database/Instance '||:dbid||'/'||:inst_num);
  end if;
  close csnapid;

end;
/
whenever sqlerror continue;


--
--  Ask how many days of snapshots to display

set termout on;
column instart_fmt noprint;
column inst_name   format a12  heading 'Instance';
column db_name     format a12  heading 'DB Name';
column snap_id     format 99999990 heading 'Snap Id';
column snapdat     format a17  heading 'Snap Started' just c;
column lvl         format 99   heading 'Snap|Level';
column commnt      format a20  heading 'Comment';

prompt
prompt
prompt Specify the number of days of snapshots to choose from
prompt ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
prompt Entering the number of days (n) will result in the most recent
prompt (n) days of snapshots being listed.  Pressing <return> without
prompt specifying a number lists all completed snapshots.
prompt
prompt

set heading off;
column num_days new_value num_days noprint;
select    'Listing '
       || decode( nvl('&&num_days', to_number('3.14','9D99','nls_numeric_characters=''.,'''))
                , to_number('3.14','9D99','nls_numeric_characters=''.,'''), 'all Completed Snapshots'
                , 0                                                       , 'no snapshots'
                , 1                                                       , 'the last day''s Completed Snapshots'
                , 'the last &num_days days of Completed Snapshots')
     , nvl('&&num_days', to_number('3.14','9D99','nls_numeric_characters=''.,'''))  num_days
  from sys.dual;
set heading on;


--
-- List available snapshots

break on inst_name on db_name on host on instart_fmt skip 1;

ttitle off;

select to_char(s.startup_time,' dd Mon "at" HH24:mi:ss') instart_fmt
     , di.instance_name                                  inst_name
     , di.db_name                                        db_name
     , s.snap_id                                         snap_id
     , to_char(s.snap_time,'dd Mon YYYY HH24:mi')        snapdat
     , s.snap_level                                      lvl
     , substr(s.ucomment, 1,60)                          commnt
  from stats$snapshot s
     , stats$database_instance di
 where s.dbid              = :dbid
   and di.dbid             = :dbid
   and s.instance_number   = :inst_num
   and di.instance_number  = :inst_num
   and di.dbid             = s.dbid
   and di.instance_number  = s.instance_number
   and di.startup_time     = s.startup_time
   and s.snap_time        >= decode( to_number('&num_days')
                                   , to_number('3.14','9D99','nls_numeric_characters=''.,'''), s.snap_time
                                   , 0                                                       , to_date('31-JAN-9999','DD-MON-YYYY')
                                   , to_date(:max_snap_time,'dd/mm/yyyy') - (to_number('&num_days') - 1))
 order by db_name, instance_name, snap_id;

clear break;
ttitle off;


--
--  Ask for the snapshots Id's which are to be compared

prompt
prompt
prompt Specify the Begin and End Snapshot Ids
prompt ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
prompt Begin Snapshot Id specified: &&begin_snap
prompt
prompt End   Snapshot Id specified: &&end_snap
prompt


--
--  Set up the snapshot-related binds

variable bid        number;
variable eid        number;
begin
  :bid       :=  &begin_snap;
  :eid       :=  &end_snap;
end;
/

prompt


--
--  Error reporting

whenever sqlerror exit;
declare

  cursor cspid(vspid stats$snapshot.snap_id%type) is
     select snap_time
          , startup_time
          , session_id
          , serial#
       from stats$snapshot
      where snap_id         = vspid
        and instance_number = :inst_num
        and dbid            = :dbid;

  bsnapt  stats$snapshot.startup_time%type;
  bstart  stats$snapshot.startup_time%type;
  bsesid  stats$snapshot.session_id%type;
  bseria  stats$snapshot.serial#%type;
  esnapt  stats$snapshot.startup_time%type;
  estart  stats$snapshot.startup_time%type;
  esesid  stats$snapshot.session_id%type;
  eseria  stats$snapshot.serial#%type;

begin

  -- Check Begin Snapshot id is valid, get corresponding instance startup time
  open cspid(:bid);
  fetch cspid into bsnapt, bstart, bsesid, bseria;
  if cspid%notfound then
    raise_application_error(-20200,
      'Begin Snapshot Id '||:bid||' does not exist for this database/instance');
  end if;
  close cspid;

  -- Check End Snapshot id is valid and get corresponding instance startup time
  open cspid(:eid);
  fetch cspid into esnapt, estart, esesid, eseria;
  if cspid%notfound then
    raise_application_error(-20200,
      'End Snapshot Id '||:eid||' does not exist for this database/instance');
  end if;
  if esnapt <= bsnapt then
    raise_application_error(-20200,
      'End Snapshot Id '||:eid||' must be greater than Begin Snapshot Id '||:bid);
  end if;
  close cspid;

  -- Check startup time is same for begin and end snapshot ids
  if ( bstart != estart) then
    raise_application_error(-20200,
      'The instance was shutdown between snapshots '||:bid||' and '||:eid);
  end if;

  -- Check sessions are same for begin and end snapshot ids
  if (bsesid != esesid or bseria != eseria) then
      dbms_output.put_line('WARNING: SESSION STATISTICS WILL NOT BE PRINTED, as session statistics');
      dbms_output.put_line('captured in begin and end snapshots are for different sessions');
      dbms_output.put_line('(Begin Snap sid,serial#: '||bsesid||','||bseria||',  End Snap sid,serial#: '||esesid||','||eseria||').');
      dbms_output.put_line('');
  end if;

end;
/
whenever sqlerror continue;


--
--  Get the database info to display in the report

set termout off;
column para       new_value para;
column versn      new_value versn;
column host_name  new_value host_name;
column db_name    new_value db_name;
column inst_name  new_value inst_name;
column btime      new_value btime;
column etime      new_value etime;
column sutime     new_value sutime;

select parallel       para
     , version        versn
     , host_name      host_name
     , db_name        db_name
     , instance_name  inst_name
     , to_char(snap_time, 'YYYYMMDD HH24:MI:SS')   btime
     , to_char(s.startup_time, 'DD-Mon-YY HH24:MI') sutime
  from stats$database_instance di
     , stats$snapshot          s
 where s.snap_id          = :bid
   and s.dbid             = :dbid
   and s.instance_number  = :inst_num
   and di.dbid            = s.dbid
   and di.instance_number = s.instance_number
   and di.startup_time    = s.startup_time;

select to_char(snap_time, 'YYYYMMDD HH24:MI:SS')  etime
  from stats$snapshot     s
 where s.snap_id          = :eid
   and s.dbid             = :dbid
   and s.instance_number  = :inst_num;

variable para       varchar2(9);
variable versn      varchar2(10);
variable host_name  varchar2(64);
variable db_name    varchar2(20);
variable inst_name  varchar2(20);
variable btime      varchar2(25);
variable etime      varchar2(25);
variable sutime     varchar2(19);
begin
  :para      := '&para';
  :versn     := '&versn';
  :host_name := '&host_name';
  :db_name   := '&db_name';
  :inst_name := '&inst_name';
  :btime     := '&btime';
  :etime     := '&etime';
  :sutime    := '&sutime';
end;
/

define DBtime=1
define DBtimes=1
column DBtime  new_value DBtime  noprint
column DBtimes new_value DBtimes noprint
select (e.value - b.value)                   DBtime
     , round((e.value - b.value)/1000000,1)  DBtimes
  from stats$sys_time_model e
     , stats$sys_time_model b
     , stats$time_model_statname sn
 where b.snap_id                = :bid
   and e.snap_id                = :eid
   and b.dbid                   = :dbid
   and e.dbid                   = :dbid
   and b.instance_number        = :inst_num
   and e.instance_number        = :inst_num
   and sn.stat_name             = 'DB time'
   and b.stat_id                = e.stat_id
   and e.stat_id                = sn.stat_id;
set termout on;


--
-- Use report name if specified, otherwise prompt user for output file 
-- name (specify default), then begin spooling

set termout off;
column dflt_name new_value dflt_name noprint;
select 'sp_'||:bid||'_'||:eid dflt_name from dual;
set termout on;

prompt
prompt Specify the Report Name
prompt ~~~~~~~~~~~~~~~~~~~~~~~
prompt The default report file name is &dflt_name..  To use this name, 
prompt press <return> to continue, otherwise enter an alternative.
prompt

set heading off;
column report_name new_value report_name noprint;
select 'Using the report name ' || nvl('&&report_name','&dflt_name')
     , decode( instr(nvl('&&report_name','&dflt_name'),'.'), 0, nvl('&&report_name','&dflt_name')||'.lst'
             , nvl('&&report_name','&dflt_name')) report_name
  from sys.dual;
prompt

spool &report_name;
set heading on;



--
--

set newpage 1 heading on;


--
--  Call statspack to calculate certain statistics
--

set termout off heading off verify off;
variable lhtr   number;
variable bfwt   number;
variable tran   number;
variable chng   number;
variable ucal   number;
variable urol   number;
variable ucom   number;
variable rsiz   number;
variable phyr   number;
variable phyrd  number;
variable phyrdl number;
variable phyrc  number;
variable phyw   number;
variable prse   number;
variable hprs   number;
variable recr   number;
variable gets   number;
variable slr    number;
variable rlsr   number;
variable rent   number;
variable srtm   number;
variable srtd   number;
variable srtr   number;
variable strn   number;
variable call   number;
variable lhr    number;
variable bsp    varchar2(512);
variable esp    varchar2(512);
variable bbc    varchar2(512);
variable ebc    varchar2(512);
variable blb    varchar2(512);
variable elb    varchar2(512);
variable bs     varchar2(512);
variable twt    number;
variable logc   number;
variable prscpu number;
variable prsela number;
variable tcpu   number;
variable exe    number;
variable bspm   number;
variable espm   number;
variable bfrm   number;
variable efrm   number;
variable blog   number;
variable elog   number;
variable bocur  number;
variable eocur  number;
variable bpgaalloc number;
variable epgaalloc number;
variable bsgaalloc number;
variable esgaalloc number;
variable bnprocs   number;
variable enprocs   number;
variable timstat   varchar2(20);
variable statlvl   varchar2(40);
-- OS Stat
variable bncpu  number;
variable encpu  number;
variable bpmem  number;
variable epmem  number;
variable blod   number;
variable elod   number;
variable itic   number;
variable btic   number;
variable iotic  number;
variable rwtic  number;
variable utic   number;
variable stic   number;
variable vmib   number;
variable vmob   number;
variable oscpuw number;
-- OS Stat derived
variable ttic   number;
variable ttics  number;
variable cpubrat number;
variable cpuirat number;
-- Time Model
variable dbtim   number;
variable dbcpu   number;
variable bgela   number;
variable bgcpu   number;
variable prstela number;
variable sqleela number;
variable conmela number;
variable bncpu   number;
-- RAC variables
variable dmsd   number;
variable dmfc   number;
variable dmsi   number;
variable pmrv   number;
variable pmpt   number;
variable npmrv   number;
variable npmpt   number;
variable dbfr   number;
variable dpms   number;
variable dnpms   number;
variable glsg   number;
variable glag   number;
variable glgt   number;
variable gccrrv   number;
variable gccrrt   number;
variable gccrfl   number;
variable gccurv   number;
variable gccurt   number;
variable gccufl   number;
variable gccrsv   number;
variable gccrbt   number;
variable gccrft   number;
variable gccrst   number;
variable gccusv   number;
variable gccupt   number;
variable gccuft   number;
variable gccust   number;
variable msgsq    number;
variable msgsqt   number;
variable msgsqk   number;
variable msgsqtk  number;
variable msgrq    number;
variable msgrqt   number;

begin
  STATSPACK.STAT_CHANGES
   ( :bid,    :eid
   , :dbid,   :inst_num
   , :para                     -- End of IN arguments
   , :lhtr,   :bfwt
   , :tran,   :chng
   , :ucal,   :urol
   , :rsiz
   , :phyr,   :phyrd
   , :phyrdl, :phyrc
   , :phyw,   :ucom
   , :prse,   :hprs
   , :recr,   :gets
   , :slr
   , :rlsr,   :rent
   , :srtm,   :srtd
   , :srtr,   :strn
   , :lhr
   , :bbc,    :ebc
   , :bsp,    :esp
   , :blb
   , :bs,     :twt
   , :logc,   :prscpu
   , :tcpu,   :exe
   , :prsela
   , :bspm,   :espm
   , :bfrm,   :efrm
   , :blog,   :elog
   , :bocur,  :eocur
   , :bpgaalloc,   :epgaalloc
   , :bsgaalloc,   :esgaalloc
   , :bnprocs,     :enprocs
   , :timstat,     :statlvl
   , :bncpu,  :encpu           -- OS Stat
   , :bpmem,  :epmem
   , :blod,   :elod
   , :itic,   :btic
   , :iotic,  :rwtic
   , :utic,   :stic
   , :vmib,   :vmob
   , :oscpuw
   , :dbtim,  :dbcpu           -- Time Model
   , :bgela,  :bgcpu
   , :prstela,:sqleela
   , :conmela
   , :dmsd,   :dmfc            -- begin RAC
   , :dmsi
   , :pmrv,   :pmpt 
   , :npmrv,  :npmpt 
   , :dbfr
   , :dpms,   :dnpms 
   , :glsg,   :glag 
   , :glgt
   , :gccrrv, :gccrrt, :gccrfl 
   , :gccurv, :gccurt, :gccufl 
   , :gccrsv
   , :gccrbt, :gccrft 
   , :gccrst, :gccusv 
   , :gccupt, :gccuft 
   , :gccust
   , :msgsq,  :msgsqt
   , :msgsqk, :msgsqtk
   , :msgrq,  :msgrqt          -- end RAC
   );
   :call    := :ucal + :recr;
   -- total ticks (cs)
   :ttic    := :btic + :itic;
    -- total ticks (s)
   :ttics   := :ttic/100;
   -- Busy to total CPU  ratio
   :cpubrat := :btic / :ttic;
   :cpuirat := :itic / :ttic;
end;
/

--
-- Print stat consistency warnings

set termout on;
set heading off;

select 'WARNING: statistics_level setting changed between begin/end snaps: Time Model'
     , '         data is INVALID'
  from dual
 where :statlvl = 'INCONSISTENT_BASIC';

select 'WARNING: timed_statistics setting changed between begin/end snaps: TIMINGS'
     , '         ARE INVALID'
  from dual
 where :timstat = 'INCONSISTENT';

set heading on;


--
--  Standard formatting

column chr4n      format a4      newline
column ch5        format a5
column ch5        format a5
column ch6        format a6
column ch6n       format a6      newline
column ch7        format a7
column ch7n       format a7      newline
column ch9        format a9
column ch14n      format a14     newline
column ch16t      format a16              trunc
column ch17       format a17
column ch17n      format a17     newline
column ch18n      format a18     newline
column ch19       format a19
column ch19n      format a19     newline
column ch21       format a21
column ch21n      format a21     newline
column ch22       format a22
column ch22n      format a22     newline
column ch23       format a23
column ch23n      format a23     newline
column ch24       format a24
column ch24n      format a24     newline
column ch25       format a25
column ch25n      format a25     newline
column ch20       format a20
column ch20n      format a20     newline
column ch32n      format a32     newline
column ch40n      format a40     newline
column ch42n      format a42     newline
column ch43n      format a43     newline
column ch52n      format a52     newline  just r
column ch53n      format a53     newline
column ch59n      format a59     newline  just r
column ch78n      format a78     newline
column ch80n      format a80     newline

column num3       format             999                 just left
column num3_2     format             999.99
column num3_2n    format             999.99     newline
column num4c      format           9,999
column num4c_2    format           9,999.99
column num4c_2n   format           9,999.99     newline
column num5c      format          99,999   
column num6c      format         999,999   
column num6c_2    format         999,999.99
column num6c_2n   format         999,999.99     newline
column num6cn     format         999,999        newline
column num7c      format       9,999,999
column num7c_2    format       9,999,999.99
column num8c      format      99,999,999
column num8cn     format      99,999,999        newline
column num8c_2    format      99,999,999.99
column num8cn     format      99,999,999        newline
column num9c      format     999,999,999
column num9cn     format     999,999,999        newline
column num10c     format   9,999,999,999




--
--  Summary Statistics
--

--
--  Print database, instance, parallel, release, host and snapshot
--  information



prompt  STATSPACK report for

set heading on;

column inst_num  heading "Inst Num"  new_value inst_num  format 99999;
column inst_name heading "Instance"  new_value inst_name format a12;
column db_name   heading "DB Name"   new_value db_name   format a12;
column dbid      heading "DB Id"     new_value dbid      format 9999999999 just center;
column host_name heading "Host"     format a16 print;
column para      heading "RAC"      format a3  print;
column versn     heading "Release"  format a11  print;
column sutime    heading "Started"  format a15 print;
column a newline;

set heading off
select 'Database',   '   DB Id   ', 'Instance    ', 'Inst Num', 'Startup Time   ', 'Release    ', 'RAC'
     , '~~~~~~~~' a, '-----------', '------------', '--------', '---------------', '-----------', '---'
     , '        ' a
     , :dbid       dbid
     , :inst_name  inst_name
     , :inst_num   inst_num
     , :sutime     sutime
     , :versn      versn
     , :para       para
  from sys.dual;


set heading off
select 'Host'      ch5
     , 'Name:'     ch7, :host_name  ch16t
     , 'Num CPUs:' ch9, :bncpu      num3
     , '      '
     , 'Phys Memory (MB):' ch17, :bpmem/1024/1024 num6c
     , '~~~~'              chr4n
  from sys.dual;
set heading on;

--
--  Print snapshot information

column inst_num   noprint
column instart_fmt new_value INSTART_FMT noprint;
column instart    new_value instart noprint;
column session_id new_value SESSION noprint;
column ela        new_value ELA     noprint;
column btim       new_value btim    heading 'Start Time' format a19 just c;
column etim       new_value etim    heading 'End Time'   format a19 just c;
column xbid        format 999999990;
column xeid        format 999999990;
column dur        heading 'Duration(mins)' format 999,990.00 just r;
column sess_id    new_value sess_id noprint;
column serial     new_value serial  noprint;
column bbgt       new_value bbgt noprint;
column ebgt       new_value ebgt noprint;
column bdrt       new_value bdrt noprint;
column edrt       new_value edrt noprint;
column bet        new_value bet  noprint;
column eet        new_value eet  noprint;
column bsmt       new_value bsmt noprint;
column esmt       new_value esmt noprint;
column bvc        new_value bvc  noprint;
column evc        new_value evc  noprint;
column bpc        new_value bpc  noprint;
column epc        new_value epc  noprint;
column bspr       new_value bspr noprint;
column espr       new_value espr noprint;
column bslr       new_value bslr noprint;
column eslr       new_value eslr noprint;
column bsbb       new_value bsbb noprint;
column esbb       new_value esbb noprint;
column bsrl       new_value bsrl noprint;
column esrl       new_value esrl noprint;
column bsiw       new_value bsiw noprint;
column esiw       new_value esiw noprint;
column bcrb       new_value bcrb noprint;
column ecrb       new_value ecrb noprint;
column bcub       new_value bcub noprint;
column ecub       new_value ecub noprint;
column blog       format 99,999;
column elog       format 99,999;
column ocs        format 99,999.0;
column comm       format a19 trunc;
column nl         newline;
column nl11       format a11 newline;
column nl16       format a16 newline;

set heading off;
select 'Snapshot       Snap Id     Snap Time      Sessions Curs/Sess Comment' nl
     , '~~~~~~~~    ---------- ------------------ -------- --------- -------------------'    nl
     , 'Begin Snap:'                                          nl11
     , b.snap_id                                                xbid
     , to_char(b.snap_time, 'dd-Mon-yy hh24:mi:ss')             btim
     , :blog                                                    blog
     , :bocur/:blog                                             ocs
     , b.ucomment                                               comm
     , '  End Snap:'                                          nl11
     , e.snap_id                                               xeid
     , to_char(e.snap_time, 'dd-Mon-yy hh24:mi:ss')             etim
     , :elog                                                    elog
     , :eocur/:elog                                             ocs
     , e.ucomment                                               comm
     , '   Elapsed:     '                                     nl16
     , round(((e.snap_time - b.snap_time) * 1440 * 60), 0)/60   dur  -- mins
     , '(mins)'
     , b.instance_number                                        inst_num
     , to_char(b.startup_time, 'dd-Mon-yy hh24:mi:ss')          instart_fmt
     , b.session_id
     , round(((e.snap_time - b.snap_time) * 1440 * 60), 0)      ela  -- secs
     , to_char(b.startup_time,'YYYYMMDD HH24:MI:SS')            instart
     , e.session_id                                             sess_id
     , e.serial#                                                serial
     , b.buffer_gets_th                                         bbgt
     , e.buffer_gets_th                                         ebgt
     , b.disk_reads_th                                          bdrt
     , e.disk_reads_th                                          edrt
     , b.executions_th                                          bet
     , e.executions_th                                          eet
     , b.sharable_mem_th                                        bsmt
     , e.sharable_mem_th                                        esmt
     , b.version_count_th                                       bvc
     , e.version_count_th                                       evc
     , b.parse_calls_th                                         bpc
     , e.parse_calls_th                                         epc
     , b.seg_phy_reads_th                                       bspr
     , e.seg_phy_reads_th                                       espr
     , b.seg_log_reads_th                                       bslr
     , e.seg_log_reads_th                                       eslr
     , b.seg_buff_busy_th                                       bsbb
     , e.seg_buff_busy_th                                       esbb
     , b.seg_rowlock_w_th                                       bsrl
     , e.seg_rowlock_w_th                                       esrl
     , b.seg_itl_waits_th                                       bsiw
     , e.seg_itl_waits_th                                       esiw
     , b.seg_cr_bks_rc_th                                       bcrb
     , e.seg_cr_bks_rc_th                                       ecrb
     , b.seg_cu_bks_rc_th                                       bcub
     , e.seg_cu_bks_rc_th                                       ecub
  from stats$snapshot b
     , stats$snapshot e
 where b.snap_id         = :bid
   and e.snap_id         = :eid
   and b.dbid            = :dbid
   and e.dbid            = :dbid
   and b.instance_number = :inst_num
   and e.instance_number = :inst_num
   and b.startup_time    = e.startup_time
   and b.snap_time       < e.snap_time;
set heading on;

variable btim    varchar2 (20);
variable etim    varchar2 (20);
variable ela     number;
variable instart varchar2 (18);
variable bbgt    number;
variable ebgt    number;
variable bdrt    number;
variable edrt    number;
variable bet     number;
variable eet     number;
variable bsmt    number;
variable esmt    number;
variable bvc     number;
variable evc     number;
variable bpc     number;
variable epc     number;
variable spctim number;
variable pct_sp_oss_cpu_diff number;
begin
   :btim    := '&btim'; 
   :etim    := '&etim'; 
   :ela     :=  &ela;
   :instart := '&instart';
   :bbgt    := &bbgt;
   :ebgt    := &ebgt;
   :bdrt    := &bdrt;
   :edrt    := &edrt;
   :bet     := &bet;
   :eet     := &eet;
   :bsmt    := &bsmt;
   :esmt    := &esmt;
   :bvc     := &bvc;
   :evc     := &evc;
   :bpc     := &bpc;
   :epc     := &epc;
   -- Statspack total CPU time (secs) - assumes Begin CPU count and End 
   -- CPU count are identical
   :spctim := :ela * :encpu;
   -- Statspack to OS Stat CPU percentage
   select decode(:ttics, null, 0, 0, 0
                ,100*(abs(:spctim-round(:ttics))/:spctim))
     into :pct_sp_oss_cpu_diff 
     from sys.dual;
end;
/

--
--

set heading off;

--
--  Cache Sizes

column chr50  format a50 newline;
column chr28  format a28 newline;
column val  format a10 just r;
column chr16 format a16;

select 'Cache Sizes                       Begin        End'            chr50
     , '~~~~~~~~~~~                  ---------- ----------'            chr50
     , '               Buffer Cache:'                                  chr28
     , lpad(to_char(round(:bbc/1024/1024),'999,999') || 'M', 10)       val
     , lpad(decode( :ebc, :bbc, null
                   , to_char(round(:ebc/&&btomb), '999,999') || 'M'), 10) val
     , ' Std Block Size:'                                              chr16
     , lpad(to_char((:bs/1024)          ,'999') || 'K',10)             val
     , '           Shared Pool Size:'                                  chr28
     , lpad(to_char(round(:bsp/1024/1024),'999,999') || 'M',10)        val
     , lpad(decode( :esp, :bsp, null
                  , to_char(round(:esp/&&btomb), '999,999') || 'M'), 10) val
     , '     Log Buffer:'                                              chr18
     , lpad(to_char(round(:blb/1024)     ,'999,999') || 'K', 10)       val
  from sys.dual;


--
--  Load Profile

column dscr     format a28 newline;
column val      format 9,999,999,999,990.99;
column sval     format 99,990.99;
column svaln    format 99,990.99 newline;
column totcalls new_value totcalls noprint
column pctval   format 990.99;
column bpctval  format 9990.99;

select 'Load Profile                            Per Second       Per Transaction'
      ,'~~~~~~~~~~~~                       ---------------       ---------------'
      ,'                  Redo size:' dscr, round(:rsiz/:ela,2)  val
                                          , round(:rsiz/:tran,2) val
      ,'              Logical reads:' dscr, round(:slr/:ela,2)  val
                                          , round(:slr/:tran,2) val
      ,'              Block changes:' dscr, round(:chng/:ela,2)  val
                                          , round(:chng/:tran,2) val
      ,'             Physical reads:' dscr, round(:phyr/:ela,2)  val
                                          , round(:phyr/:tran,2) val
      ,'            Physical writes:' dscr, round(:phyw/:ela,2)  val
                                          , round(:phyw/:tran,2) val
      ,'                 User calls:' dscr, round(:ucal/:ela,2)  val
                                          , round(:ucal/:tran,2) val
      ,'                     Parses:' dscr, round(:prse/:ela,2)  val
                                          , round(:prse/:tran,2) val
      ,'                Hard parses:' dscr, round(:hprs/:ela,2)  val
                                          , round(:hprs/:tran,2) val
      ,'                      Sorts:' dscr, round((:srtm+:srtd)/:ela,2)  val
                                          , round((:srtm+:srtd)/:tran,2) val
      ,'                     Logons:' dscr, round(:logc/:ela,2)  val
                                          , round(:logc/:tran,2) val
      ,'                   Executes:' dscr, round(:exe/:ela,2)   val
                                          , round(:exe/:tran,2)  val
      ,'               Transactions:' dscr, round(:tran/:ela,2)  val
      , '                           ' dscr
      ,'  % Blocks changed per Read:' dscr,  round(100*:chng/:slr,2)  pctval
      ,'   Recursive Call %:'         chr20, round(100*:recr/:call,2) bpctval
      ,' Rollback per transaction %:' dscr,  round(100*:urol/:tran,2) pctval
      ,'      Rows per Sort:'         chr20, decode((:srtm+:srtd)
                                                   ,0,to_number(null)
                                                   ,round(:srtr/(:srtm+:srtd),2)) bpctval
 from sys.dual;


--
--  Instance Efficiency Percentages

column ldscr  format a50
column chr20  format a20
column nl format a60 newline

select 'Instance Efficiency Percentages'               ldscr
      ,'~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~'               ldscr
      ,'            Buffer Nowait %:'                  dscr
      , round(100*(1-:bfwt/:gets),2)                   pctval
      ,'      Redo NoWait %:'                          chr20
      , decode(:rent,0,to_number(null), round(100*(1-:rlsr/:rent),2))  pctval
      ,'            Buffer  Hit   %:'                  dscr
      , round(100*(1 - :phyrc/:gets),2)                pctval
      ,'   In-memory Sort %:'                          chr20
      , decode((:srtm+:srtd),0,to_number(null),
                               round(100*:srtm/(:srtd+:srtm),2))       pctval
      ,'            Library Hit   %:'                  dscr
      , round(100*:lhtr,2)                             pctval
      ,'       Soft Parse %:'                          chr20
      , round(100*(1-:hprs/:prse),2)                   pctval
      ,'         Execute to Parse %:'                  dscr
      , round(100*(1-:prse/:exe),2)                    pctval
      ,'        Latch Hit %:'                          chr20
      , round(100*(1-:lhr),2)                          pctval
      ,'Parse CPU to Parse Elapsd %:'                  dscr
      , decode(:prsela, 0, to_number(null)
                      , round(100*:prscpu/:prsela,2))  pctval
      ,'    % Non-Parse CPU:'                          chr20
      , decode(:tcpu, 0, to_number(null)
                    , round(100*(1-(:prscpu/:tcpu)),2))  pctval
  from sys.dual;

-- Setup vars in case snap < 5 taken
define b_total_cursors = 0
define e_total_cursors = 0
define b_total_sql     = 0
define e_total_sql     = 0
define b_total_sql_mem = 0
define e_total_sql_mem = 0

column b_total_cursors new_value b_total_cursors noprint
column e_total_cursors new_value e_total_cursors noprint
column b_total_sql     new_value b_total_sql     noprint
column e_total_sql     new_value e_total_sql     noprint
column b_total_sql_mem new_value b_total_sql_mem noprint
column e_total_sql_mem new_value e_total_sql_mem noprint

select  ' Shared Pool Statistics        Begin   End'        nl
      , '                               ------  ------'
      , '             Memory Usage %:'                 dscr
      , 100*(1-:bfrm/:bspm)                            pctval
      , 100*(1-:efrm/:espm)                            pctval
      , '    % SQL with executions>1:'                 dscr
      , 100*(1-b.single_use_sql/b.total_sql)           pctval
      , 100*(1-e.single_use_sql/e.total_sql)           pctval
      , '  % Memory for SQL w/exec>1:'                 dscr
      , 100*(1-b.single_use_sql_mem/b.total_sql_mem)   pctval
      , 100*(1-e.single_use_sql_mem/e.total_sql_mem)   pctval
      , nvl(b.total_cursors, 0)                        b_total_cursors
      , nvl(e.total_cursors, 0)                        e_total_cursors
      , nvl(b.total_sql, 0)                            b_total_sql
      , nvl(e.total_sql, 0)                            e_total_sql
      , nvl(b.total_sql_mem, 0)                        b_total_sql_mem
      , nvl(e.total_sql_mem, 0)                        e_total_sql_mem
  from stats$sql_statistics b
     , stats$sql_statistics e
 where b.snap_id         = :bid
   and e.snap_id         = :eid
   and b.instance_number = :inst_num
   and e.instance_number = :inst_num
   and b.dbid            = :dbid
   and e.dbid            = :dbid;

variable b_total_cursors number;
variable e_total_cursors number;
variable b_total_sql     number;
variable e_total_sql     number;
variable b_total_sql_mem number;
variable e_total_sql_mem number;
begin
  :b_total_cursors := &&b_total_cursors;
  :e_total_cursors := &&e_total_cursors;
  :b_total_sql     := &&b_total_sql;
  :e_total_sql     := &&e_total_sql;
  :b_total_sql_mem := &&b_total_sql_mem;
  :e_total_sql_mem := &&e_total_sql_mem;
end;
/


--
--

set heading on;
repfooter center -
   '-------------------------------------------------------------';

--
--  Top N Wait Events

col idle     noprint;
col event    format a41          heading 'Top &&top_n_events Timed Events|~~~~~~~~~~~~~~~~~~|Event' trunc;
col waits    format 999,999,990  heading 'Waits';
col time     format 99,999,990   heading 'Time (s)';
col pctwtt   format 999.9        heading '%Total|Call|Time';
col avwait   format 99990        heading 'Avg|wait|(ms)';

select event
     , waits
     , time
     , avwait
     , pctwtt
  from (select event, waits, time, pctwtt, avwait
          from (select e.event                               event
                     , e.total_waits - nvl(b.total_waits,0)  waits
                     , (e.time_waited_micro - nvl(b.time_waited_micro,0))/1000000  time
                     , decode ( (e.total_waits - nvl(b.total_waits, 0)), 0, to_number(NULL)
                             ,    ( (e.time_waited_micro - nvl(b.time_waited_micro,0)) / &&ustoms )
                                / (e.total_waits - nvl(b.total_waits,0))
                             )        avwait
                     , decode(:twt + :tcpu*10000, 0, 0,
                                100
                              * (e.time_waited_micro - nvl(b.time_waited_micro,0))
                              / (:twt + :tcpu*10000)                        
                              )                              pctwtt
                 from stats$system_event b
                    , stats$system_event e
                where b.snap_id(+)          = :bid
                  and e.snap_id             = :eid
                  and b.dbid(+)             = :dbid
                  and e.dbid                = :dbid
                  and b.instance_number(+)  = :inst_num
                  and e.instance_number     = :inst_num
                  and b.event(+)            = e.event
                  and e.total_waits         > nvl(b.total_waits,0)
                  and e.event not in (select event from stats$idle_event)
               union all
               select 'CPU time'                              event
                    , to_number(null)                         waits
                    , :tcpu/100                               time
                    , to_number(null)                         avwait
                    , decode(:twt + :tcpu*10000, 0, 0,
                               100
                             * :tcpu*10000 
                             / (:twt + :tcpu*10000)
                            )                                 pctwait
                 from dual
                where :tcpu > 0
               )
         order by time desc, waits desc
       )
 where rownum <= &&top_n_events;



--
--

set space 1 termout on newpage 1;
whenever sqlerror exit;

set heading off;
repfooter off;


--
-- Performance Summary continued

set newpage 0;

ttitle off;

select 'Host CPU  ' || decode(:bncpu, :encpu, '(CPUs: '|| :bncpu || ')',  '(Begin CPUs: '|| :bncpu || ' End CPUs: '|| :encpu || ')') ch78n
     , '~~~~~~~~              Load Average'                                              ch78n
     , '                      Begin     End      User  System    Idle     WIO     WCPU'  ch78n
     , '                    ------- -------   ------- ------- ------- ------- --------'  ch78n
     , '                   '
     , round(:blod,2)          pctval
     , round(:elod,2)          pctval
     , ' '
     , 100*(:utic   / :ttic)   pctval
     , 100*(:stic   / :ttic)   pctval
     , 100*(:itic   / :ttic)   pctval
     , 100*(:iotic  / :ttic)   pctval
     , 100*(:oscpuw / :ttic)   pctval
  from sys.dual
 where :ttic > 0;

set newpage 1;

select 'Note: There is a ' || round(:pct_sp_oss_cpu_diff) || '% discrepancy between the OS Stat total CPU time and'
     , '      the total CPU time estimated by Statspack'
     , '          OS Stat CPU time: ' || round(:ttics)  || '(s) (BUSY_TIME + IDLE_TIME)'
     , '        Statspack CPU time: ' || :spctim || '(s) (Elapsed time * num CPUs in end snap)'
  from sys.dual
 where &pct_cpu_diff_th < :pct_sp_oss_cpu_diff
   and :ttics > 0;

select 'Instance CPU'                               ch40n
     , '~~~~~~~~~~~~'                               ch40n
     , '              % of total CPU for Instance:' ch45n, 100* ((:dbcpu+:bgcpu)/1000000)
                                                              / (:ttics)               pctval
     , '              % of busy  CPU for Instance:' ch45n, 100* ((:dbcpu+:bgcpu)/1000000)
                                                              / ((:btic)/100)          pctval
     , '  %DB time waiting for CPU - Resource Mgr:' ch45n, decode(:rwtic, 0, to_number(null), 
                                                           100*(round(:rwtic/:dbtim)) )  pctval
  from sys.dual
 where :dbtim    > 0
   and :btic/100 > 0;

column kpersec format 999,999,999.9
select 'Virtual Memory Paging' ch78n
     , '~~~~~~~~~~~~~~~~~~~~~' ch78n
     , '                     KB paged out per sec: ' ch43n, (:vmob/1024)/:ela  kpersec
     , '                     KB paged  in per sec: ' ch43n, (:vmib/1024)/:ela  kpersec
  from sys.dual
 where :vmob + :vmib > 0;

col bpctval format 999999999.9
repfooter center -
   '-------------------------------------------------------------';
col memsz format 9,999,999.9
select 'Memory Statistics                       Begin          End' ch79n
     , '~~~~~~~~~~~~~~~~~                ------------ ------------' ch79n
     , '                  Host Mem (MB):' ch32n, :bpmem/&&btomb memsz, :epmem/&&btomb memsz
     , '                   SGA use (MB):' ch32n, :bsgaalloc/&&btomb memsz, :esgaalloc/&&btomb memsz
     , '                   PGA use (MB):' ch32n, :bpgaalloc/&&btomb memsz, :epgaalloc/&&btomb memsz
     , '    % Host Mem used for SGA+PGA:' ch32n, 100*(:bpgaalloc + :bsgaalloc)/:bpmem bpctval
                                               , 100*(:epgaalloc + :esgaalloc)/:epmem bpctval
  from sys.dual;

repfooter off

--
--

set space 1 termout on newpage 0;
whenever sqlerror exit;
repfooter center -
   '-------------------------------------------------------------';

--
--  Time Model Statistics

set newpage 1;
set heading on;

ttitle lef 'Time Model System Stats  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
       lef '-> Ordered by % of DB time desc, Statistic name' -
       skip 2;

column statnam format a35 trunc              heading 'Statistic'
column tdifs   format 9,999,999,999,990.9    heading 'Time (s)'
column pctdb   format 99999.9                heading '% of DB time'
column order_col noprint

select statnam
     , tdif/&ustos                        tdifs
     , decode(order_col, 0, 100*tdif/&DBtime
                       , to_number(null)
             )                            pctdb
     , order_col
  from (select sn.stat_name               statnam
             , (e.value - b.value)        tdif
             , decode( sn.stat_name
                     , 'DB time',                 1
                     , 'background cpu time',     2
                     , 'background elapsed time', 2
                     , 0
                     )                    order_col
          from stats$sys_time_model e
             , stats$sys_time_model b
             , stats$time_model_statname sn
         where b.snap_id                = :bid
           and e.snap_id                = :eid
           and b.dbid                   = :dbid
           and e.dbid                   = :dbid
           and b.instance_number        = :inst_num
           and e.instance_number        = :inst_num
           and b.stat_id                = e.stat_id
           and sn.stat_id               = e.stat_id
           and e.value - b.value        > 0
       )
 order by order_col, decode(pctdb, null, tdifs, pctdb) desc;



set heading off;
set newpage 0;

--
-- Beginning of RAC specific Ratios


column hd1      format a54 newline;
column hd2      format a31 newline;
column avg      format 9990.0;
column nl       format a68 newline;
column val      format 9,999,999,999,990.99;
column vali     format 9990;

ttitle lef 'RAC Statistics  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 2;

select ' '                                                                     hd2
     , 'Begin'
     , '  End'
     , ' '                                                                     hd2
     , '-----'
     , '-----'
     , '           Number of Instances:'                                       hd2
     , ( select count(b.thread#)
           from stats$thread b
          where b.snap_id         = :bid
            and b.dbid            = :dbid
            and b.instance_number = :inst_num
            and b.status          = 'OPEN' )                                   vali
     , ( select count(e.thread#)
           from stats$thread e
          where e.snap_id         = :eid
            and e.dbid            = :dbid
            and e.instance_number = :inst_num
            and e.status          = 'OPEN' )                                   vali
     , ' '                                                                     nl
     , ' '                                                                     nl
     , 'Global Cache Load Profile' nl
     , '~~~~~~~~~~~~~~~~~~~~~~~~~                  Per Second       Per Transaction'
     , '                                      ---------------       ---------------'
     , '  Global Cache blocks received:' hd2, round((:gccurv+:gccrrv)/:ela,2)  val
                                            , round((:gccurv+:gccrrv)/:tran,2) val
     , '    Global Cache blocks served:' hd2, round((:gccusv+:gccrsv)/:ela,2)  val
                                            , round((:gccusv+:gccrsv)/:tran,2) val
     , '     GCS/GES messages received:' hd2, round((:pmrv+:npmrv)/:ela,2)     val
                                            , round((:pmrv+:npmrv)/:tran,2)    val
     , '         GCS/GES messages sent:' hd2, round((:dpms+:dnpms)/:ela,2)     val
                                            , round((:dpms+:dnpms)/:tran,2)    val
     , '            DBWR Fusion writes:' hd2, round(:dbfr/:ela,2)              val
                                            , round(:dbfr/:tran,2)             val
     , 'Estd Interconnect traffic (KB):' hd2, round( (  ((:gccrrv+:gccurv +:gccrsv+:gccusv) * :bs)
                                                      + ((:dpms+:dnpms+:pmrv+:npmrv)        * 200)
                                                     )/&&btokb/:ela,2
                                                   )                           val
     , ' '                                                                     nl
     , ' '                                                                     nl
     , 'Global Cache Efficiency Percentages (Target local+remote 100%)'        nl
     , '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~'        nl
     , 'Buffer access -  local cache %:'                                       hd2
     , round(100*(1- (:phyrc +:gccrrv+:gccurv)/:gets), 2)                      pctval
     , 'Buffer access - remote cache %:'                                       hd2
     , round(100* (:gccurv+:gccrrv)/:gets, 2)                                  pctval
     , 'Buffer access -         disk %:'                                       hd2
     , round(100 * :phyrc/:gets, 2)                                            pctval
     , ' '                                                                     nl
     , ' '                                                                     nl
     , 'Global Cache and Enqueue Services - Workload Characteristics'          nl
     , '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~'          nl
     , '                     Avg global enqueue get time (ms):'                hd1
     , decode(:glag+:glsg, 0, to_number(NULL)
                         , (:glgt / (:glag+:glsg)) * 10)                       avg
     , ' '                                                                     nl
     , '          Avg global cache cr block receive time (ms):'                hd1
     , decode(:gccrrv, 0, to_number(NULL)
                     , 10 * :gccrrt / :gccrrv)                                 avg
     , '     Avg global cache current block receive time (ms):'                hd1
     , decode(:gccurv, 0, to_number(NULL)
                     , 10 * :gccurt / :gccurv)                                 avg
     , ' '                                                                     nl
     , '            Avg global cache cr block build time (ms):'                hd1
     , decode(:gccrsv, 0, to_number(NULL)
                     , 10 * :gccrbt / :gccrsv)                                 avg
     , '             Avg global cache cr block send time (ms):'                hd1
     , decode(:gccrsv, 0, to_number(NULL)
                     , 10 * :gccrst / :gccrsv)                                 avg
     , '            Avg global cache cr block flush time (ms):'                hd1
     , decode(:gccrfl, 0, to_number(NULL)
                     , 10 * :gccrft / :gccrfl)                                 avg
     , '      Global cache log flushes for cr blocks served %:'                hd1
     , 100*(decode(:gccrsv, 0, to_number(NULL), :gccrfl/:gccrsv))              avg
     , ' '                                                                     nl
     , '         Avg global cache current block pin time (ms):'                hd1
     , decode(:gccusv, 0, to_number(NULL)
                     , 10 * :gccupt / :gccusv)                                 avg
     , '        Avg global cache current block send time (ms):'                hd1
     , decode(:gccusv, 0, to_number(NULL)
                     , 10 * :gccust / :gccusv)                                 avg
     , '       Avg global cache current block flush time (ms):'                hd1
     , decode(:gccufl, 0, to_number(NULL)
                     , 10 * :gccuft / :gccufl)                                 avg
     , ' Global cache log flushes for current blocks served %:'                hd1
     , 100*(decode(:gccusv, 0, to_number(NULL), :gccufl/:gccusv))              avg
     , ' '                                                                     nl
     , ' '                                                                     nl
     , 'Global Cache and Enqueue Services - Messaging Statistics'              nl
     , '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~'              nl
     , '                     Avg message sent queue time (ms):'                hd1
     , decode(:msgsq, 0, to_number(NULL), :msgsqt / :msgsq)                    avg
     , '             Avg message sent queue time on ksxp (ms):'                hd1
     , decode(:msgsqk, 0, to_number(NULL), :msgsqtk / :msgsqk)                 avg
     , '                 Avg message received queue time (ms):'                hd1
     , decode(:msgrq, 0, to_number(NULL), :msgrqt / :msgrq)                    avg
     , '                    Avg GCS message process time (ms):'                hd1
     , decode(:pmrv, 0, to_number(NULL), :pmpt / :pmrv)                        avg
     , '                    Avg GES message process time (ms):'                hd1
     , decode(:npmrv, 0, to_number(NULL), :npmpt / :npmrv)                     avg
     , ' '                                                                     nl
     , '                            % of direct sent messages:'                hd1
     , decode((:dmsd + :dmsi + :dmfc), 0 , to_number(NULL)
                           , (100 * :dmsd) / (:dmsd + :dmsi + :dmfc))          pctval
     , '                          % of indirect sent messages:'                hd1
     , decode((:dmsd + :dmsi + :dmfc), 0, to_number(NULL)
                           , (100 * :dmsi) / (:dmsd + :dmsi + :dmfc))          pctval
     , '                        % of flow controlled messages:'                hd1
     , decode((:dmsd+:dmsi+:dmfc), 0, to_number(NULL)
                                    , 100 * :dmfc / (:dmsd+:dmsi+:dmfc))       pctval
  from sys.dual
 where :para = 'YES';

--
-- End of RAC specific Ratios

set heading on newpage 0;


--
--  System Events

ttitle lef 'Wait Events  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
           '-> s - second, cs - centisecond,  ms - millisecond, us - microsecond' -
       skip 1 -
           '-> %Timeouts:  value of 0 indicates value was < .5%.  Value of null is truly 0' -
       skip 1 -
           '-> Only events with Total Wait Time (s) >= &&total_event_time_s_th are shown' -
       skip 1 -
       lef '-> ordered by Total Wait Time desc, Waits desc (idle events last)' -
       skip 2;

col idle noprint;
col event    format a33         heading 'Event' trunc;
col waits    format 999,999,990 heading 'Waits';
col timeouts format 9,999,990   heading 'Timeouts';
col pctto    format 9999        heading '%Time| -outs';
col time     format 9,999,990   heading 'Total Wait|Time (s)';
col avwt_fmt format &&avwt_fmt  heading 'Avg|wait|(ms)';
col txwaits  format 9,990.0     heading 'Waits|/txn';

select e.event 
     , e.total_waits - nvl(b.total_waits,0)                        waits
     , decode( (e.total_waits - nvl(b.total_waits,0)), 0, to_number(null)
              , 100*(e.total_timeouts - nvl(b.total_timeouts,0))
                   /(e.total_waits - nvl(b.total_waits,0)))        pctto
     , (e.time_waited_micro - nvl(b.time_waited_micro,0))/1000000  time
     , decode ((e.total_waits - nvl(b.total_waits, 0)),
                0, to_number(NULL),
                  ((e.time_waited_micro - nvl(b.time_waited_micro,0))/1000)
                 / (e.total_waits - nvl(b.total_waits,0)) )        avwt_fmt
     , (e.total_waits - nvl(b.total_waits,0))/:tran                txwaits
     , decode(i.event, null, 0, 99)                                idle
  from stats$system_event b
     , stats$system_event e
     , stats$idle_event   i
 where b.snap_id(+)          = :bid
   and e.snap_id             = :eid
   and b.dbid(+)             = :dbid
   and e.dbid                = :dbid
   and b.instance_number(+)  = :inst_num
   and e.instance_number     = :inst_num
   and b.event(+)            = e.event
   and e.total_waits  > nvl(b.total_waits,0)
   and (        :timstat      in ('FALSE', 'INCONSISTENT')     -- No valid timings - use # waits to filter
        or (    :timstat       = 'TRUE'                        -- Valid timings - only show if time > threshold ms
            and ((e.time_waited_micro - nvl(b.time_waited_micro,0))/&&ustos) >= &&total_event_time_s_th
           )
       )
   and e.event       not in ('smon timer','pmon timer','dispatcher timer','dispatcher listen timer','rdbms ipc message')
   and i.event(+)            = e.event
 order by idle, time desc, waits desc;



--
--  Background process wait events

ttitle lef 'Background Wait Events  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
           '-> %Timeouts:  value of 0 indicates value was < .5%.  Value of null is truly 0' -
       skip 1 -
           '-> Only events with Total Wait Time (s) >= &&total_event_time_s_th are shown' -
       skip 1 -
       lef '-> ordered by Total Wait Time desc, Waits desc (idle events last)' -
       skip 2;

break on idle;
select e.event
     , e.total_waits - nvl(b.total_waits,0)                        waits
     , decode( (e.total_waits - nvl(b.total_waits,0)), 0, to_number(null)
              , 100*(e.total_timeouts - nvl(b.total_timeouts,0))
                   /(e.total_waits - nvl(b.total_waits,0)))        pctto
     , (e.time_waited_micro - nvl(b.time_waited_micro,0))/1000000  time
     , decode ((e.total_waits - nvl(b.total_waits, 0)),
               0, to_number(NULL),
                  ((e.time_waited_micro - nvl(b.time_waited_micro,0))/1000)
                 / (e.total_waits - nvl(b.total_waits,0)) )        avwt_fmt
     , (e.total_waits - nvl(b.total_waits,0))/:tran                txwaits
     , decode(i.event, null, 0, 99)                                idle
  from stats$bg_event_summary   b
     , stats$bg_event_summary   e
     , stats$idle_event         i
 where b.snap_id(+)         = :bid
   and e.snap_id            = :eid
   and b.dbid(+)            = :dbid
   and e.dbid               = :dbid
   and b.instance_number(+) = :inst_num
   and e.instance_number    = :inst_num
   and b.event(+)           = e.event
   and e.total_waits        > nvl(b.total_waits,0)
   and (        :timstat      in ('FALSE', 'INCONSISTENT')     -- No valid timings - use # waits to filter
        or (    :timstat       = 'TRUE'                        -- Valid timings - only show if time > 1ms
            and ((e.time_waited_micro - nvl(b.time_waited_micro,0))/&&ustos) >= &&total_event_time_s_th
           )
       )
   and i.event(+)           = e.event
 order by idle, time desc, waits desc;
clear break;



--
--  Event Histogram

ttitle lef 'Wait Event Histogram  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
       lef '-> Total Waits - units: K is 1000, M is 1000000, G is 1000000000' -
       skip 1 -
       lef '-> % of Waits - column heading: <=1s is truly <1024ms, >1s is truly >=1024ms' -
       skip 1 -
       lef '-> % of Waits - value: .0 indicates value was <.05%, null is truly 0' -
       skip 1 -
       lef '-> Ordered by Event (idle events last)' -
       skip 2 -
           '                           Total ----------------- % of Waits ------------------';

col idle noprint;
col event       format a26 heading 'Event' 
col total_waits format a5  heading 'Waits'
col to1         format a5  heading ' <1ms'
col to2         format a5  heading ' <2ms'
col to4         format a5  heading ' <4ms'
col to8         format a5  heading ' <8ms'
col to16        format a5  heading '<16ms'
col to32        format a5  heading '<32ms'
col to1024      format a5  heading ' <=1s'
col over        format a5  heading '  >1s'

with event_histogram as (
  select /*+ inline ordered index(h) index(se) */
         h.snap_id
       , se.event
       , sum(h.wait_count) total_waits
       , sum(case when (h.wait_time_milli = 1)
                  then (nvl(h.wait_count,0)) else 0 end) to1
       , sum(case when (h.wait_time_milli = 2)
                  then (nvl(h.wait_count,0)) else 0 end) to2
       , sum(case when (h.wait_time_milli = 4)
                  then (nvl(h.wait_count,0)) else 0 end) to4
       , sum(case when (h.wait_time_milli = 8)
                  then (nvl(h.wait_count,0)) else 0 end) to8
       , sum(case when (h.wait_time_milli = 16)
                  then (nvl(h.wait_count,0)) else 0 end) to16
       , sum(case when (h.wait_time_milli = 32)
                  then (nvl(h.wait_count,0)) else 0 end) to32
       , sum(case when (h.wait_time_milli between 64 and 1024)
                  then (nvl(h.wait_count,0)) else 0 end) to1024
       , sum(case when (1024 < h.wait_time_milli)
                  then (nvl(h.wait_count,0)) else 0 end) over
       , decode(i.event, null, 0, 99)                    idle
    from stats$event_histogram h
       , stats$system_event    se
       , stats$idle_event      i
   where se.event_id           = h.event_id
     and se.snap_id            = h.snap_id
     and i.event(+)            = se.event
     and se.instance_number    = :inst_num
     and se.dbid               = :dbid
     and h.instance_number     = :inst_num
     and h.dbid                = :dbid
     and '&event_histogram' = 'Y'
   group by h.snap_id
       , se.event
       , decode(i.event, null, 0, 99)
  )
select e.event
     , lpad(case
              when e.total_waits - nvl(b.total_waits,0) <= 9999
                   then to_char(e.total_waits - nvl(b.total_waits,0))||' '
              when trunc((e.total_waits - nvl(b.total_waits,0))/1000) <= 9999
                   then to_char(trunc((e.total_waits - nvl(b.total_waits,0))/1000))||'K'
              when trunc((e.total_waits - nvl(b.total_waits,0))/1000000) <= 9999
                   then to_char(trunc((e.total_waits - nvl(b.total_waits,0))/1000000))||'M'
              when trunc((e.total_waits - nvl(b.total_waits,0))/1000000000) <= 9999
                   then to_char(trunc((e.total_waits - nvl(b.total_waits,0))/1000000000))||'G'
              when trunc((e.total_waits - nvl(b.total_waits,0))/1000000000000) <= 9999
                   then to_char(trunc((e.total_waits - nvl(b.total_waits,0))/1000000000000))||'T'
              else substr(to_char(trunc((e.total_waits - nvl(b.total_waits,0))/1000000000000000))||'P', 1, 5) end
            , 5, ' ')                                                              total_waits
     , substr(to_char(decode(e.to1-nvl(b.to1,0),0,to_number(NULL),(e.to1-nvl(b.to1,0))*100/(e.total_waits-nvl(b.total_waits,0))),'999.9MI'),1,5) to1
     , substr(to_char(decode(e.to2-nvl(b.to2,0),0,to_number(NULL),(e.to2-nvl(b.to2,0))*100/(e.total_waits-nvl(b.total_waits,0))),'999.9MI'),1,5) to2
     , substr(to_char(decode(e.to4-nvl(b.to4,0),0,to_number(NULL),(e.to4-nvl(b.to4,0))*100/(e.total_waits-nvl(b.total_waits,0))),'999.9MI'),1,5) to4
     , substr(to_char(decode(e.to8-nvl(b.to8,0),0,to_number(NULL),(e.to8-nvl(b.to8,0))*100/(e.total_waits-nvl(b.total_waits,0))),'999.9MI'),1,5) to8
     , substr(to_char(decode(e.to16-nvl(b.to16,0),0,to_number(NULL),(e.to16-nvl(b.to16,0))*100/(e.total_waits-nvl(b.total_waits,0))),'999.9MI'),1,5) to16
     , substr(to_char(decode(e.to32-nvl(b.to32,0),0,to_number(NULL),(e.to32-nvl(b.to32,0))*100/(e.total_waits-nvl(b.total_waits,0))),'999.9MI'),1,5) to32
     , substr(to_char(decode(e.to1024-nvl(b.to1024,0),0,to_number(NULL),(e.to1024-nvl(b.to1024,0))*100/(e.total_waits-nvl(b.total_waits,0))),'999.9MI'),1,5) to1024
     , substr(to_char(decode(e.over-nvl(b.over,0),0,to_number(NULL),(e.over-nvl(b.over,0))*100/(e.total_waits-nvl(b.total_waits,0))),'999.9MI'),1,5) over
  from ( select *
           from event_histogram
          where snap_id          = :bid) b
     , ( select *
           from event_histogram
          where snap_id          = :eid) e
 where b.event(+) = e.event
   and (e.total_waits - nvl(b.total_waits,0)) > 0
 order by e.idle, e.event;


--
--  SQL Reporting


-- Get the captured vs total workloads ratios

set newpage none;
set heading off;
set termout off;
ttitle off;
repfooter off;

col bufcappct new_value bufcappct noprint
col getsa     new_value getsa     noprint
col phycappct new_value phycappct noprint
col phyra     new_value phyra     noprint
col execappct new_value execappct noprint
col exea      new_value exea      noprint
col prscappct new_value prscappct noprint
col prsea     new_value prsea     noprint
col cpucappct new_value cpucappct noprint
col elacappct new_value elacappct noprint
col dbcpua    new_value dbcpua    noprint
col dbcpu_s   new_value dbcpu_s   noprint
col dbtima    new_value dbtima    noprint
col dbtim_s   new_value dbtim_s   noprint

select decode( :slr, 0, to_number(null)
             , 100*sum(
               case e.command_type
                 when 47 then 0
                 else e.buffer_gets - nvl(b.buffer_gets,0)
                end)/:slr
             )                                             bufcappct
     , :slr                                                getsa
     , decode( :phyr, 0, to_number(null)
             , 100*sum(
                 case e.command_type
                   when 47 then 0
                   else e.disk_reads - nvl(b.disk_reads,0)
                 end)/:phyr
             )                                             phycappct
     , :phyr                                               phyra
     , decode( :exe, 0, to_number(null)
             , 100*sum(e.executions - nvl(b.executions,0))/:exe
             )                                             execappct 
     , :exe                                                exea
     , decode( :prse, 0, to_number(null)
             , 100*sum(e.parse_calls - nvl(b.parse_calls,0))/:prse
             )                                             prscappct
     , :prse                                               prsea
     , decode( :dbcpu, 0, to_number(null)
             , 100*sum(e.cpu_time - nvl(b.cpu_time,0))/:dbcpu
             )                                             cpucappct
     , decode(:dbcpu, 0, to_number(null), :dbcpu)          dbcpua
     , decode(:dbcpu, 0, to_number(null), :dbcpu/1000000)  dbcpu_s
     , decode( :dbtim, 0, to_number(null)
             , 100*sum(e.elapsed_time - nvl(b.elapsed_time,0))/:dbtim
             )                                             elacappct
     , decode(:dbtim, 0, to_number(null), :dbtim)          dbtima
     , decode(:dbtim, 0, to_number(null), :dbtim/1000000)  dbtim_s
  from stats$sql_summary e
     , stats$sql_summary b
 where b.snap_id(+)         = :bid
   and e.snap_id            = :eid
   and b.dbid(+)            = :dbid
   and e.dbid               = :dbid
   and b.instance_number(+) = :inst_num
   and e.instance_number    = :inst_num
   and e.executions         > nvl(b.executions,0)
   and b.old_hash_value(+)  = e.old_hash_value
   and b.address(+)         = e.address
   and b.text_subset(+)     = e.text_subset;


set newpage 0;
set termout on;
set heading on;
repfooter center -
   '-------------------------------------------------------------';

col Execs     format 999,999,990    heading 'Executes';
col GPX       format 999,999,990.0  heading 'Gets|per Exec'  just c;
col RPX       format 999,999,990.0  heading 'Reads|per Exec' just c;
col RWPX      format 9,999,990.0    heading 'Rows|per Exec'  just c;
col Gets      format 9,999,999,990  heading 'Buffer Gets';
col Reads     format 9,999,999,990  heading 'Physical|Reads';
col Rw        format 9,999,999,990  heading 'Rows | Processed';
col hashval   format 99999999999    heading 'Hash Value';
col sql_text  format a500           heading 'SQL statement'  wrap;
col rel_pct   format 999.9          heading '% of|Total';
col shm       format 999,999,999    heading 'Sharable   |Memory (bytes)';
col vcount    format 9,999          heading 'Version|Count';


--
--  SQL statements ordered by CPU

ttitle lef 'SQL ordered by CPU  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
           '-> Resources reported for PL/SQL code includes the ' -
           'resources used by all SQL' -
       skip 1 -
           '   statements called by the code.' -
       skip 1 -
           '-> Total DB CPU (s): ' format 99,999,999,999 dbcpu_s -
       skip 1 -
           '-> Captured SQL accounts for ' format 990.9 cpucappct '% of Total DB CPU' -
       skip 1 -
           '-> SQL reported below exceeded  &top_pct_sql.% of Total DB CPU' -
       skip 2;

-- Bug 1313544 requires this rather bizarre SQL statement

set underline off;
col aa format a80 heading -
'    CPU                  CPU per             Elapsd                     Old|  Time (s)   Executions  Exec (s)  %Total   Time (s)    Buffer Gets  Hash Value |---------- ------------ ---------- ------ ---------- --------------- ----------' 

column hv noprint;
break on hv skip 1;

select aa, hv
  from ( select /*+ ordered use_nl (b st) */
          decode( st.piece
                , 0
                , lpad(  nvl(to_char(  (e.cpu_time - nvl(b.cpu_time,0))/1000000
                                   , '999990.00')
                       , ' '),10) || ' ' ||
                  lpad(to_char((e.executions - nvl(b.executions,0))
                              ,'999,999,999')
                      ,12)||' '||
                  lpad((to_char(decode(e.executions - nvl(b.executions,0)
                                      ,0, to_number(null)
                                      ,  ( (e.cpu_time - nvl(b.cpu_time,0))
                                          /(e.executions - nvl(b.executions,0))
                                         ) / 1000000
                                      )
                               , '999990.00'))
                      , 10) || ' ' ||
                  lpad( decode( :dbcpu, 0   , ' '
                                      , null, ' '
                              , to_char((100*(e.cpu_time - nvl(b.cpu_time,0))/:dbcpu), '990.0')
                              )
                      , 6) ||' '||
                  lpad(  nvl(to_char(  (e.elapsed_time - nvl(b.elapsed_time,0))/1000000
                                   , '999990.00')
                       , ' '),10) || ' ' ||
                  lpad(to_char((e.buffer_gets - nvl(b.buffer_gets,0))
                               ,'99,999,999,999')
                      ,15)||' '||
                  lpad(e.old_hash_value,10)||' '||
                  decode(e.module,null,st.sql_text
                                      ,rpad('Module: '||e.module,80)||st.sql_text)
                , st.sql_text) aa
          , e.old_hash_value hv
       from stats$sql_summary e
          , stats$sql_summary b
          , stats$sqltext     st 
      where b.snap_id(+)         = :bid
        and b.dbid(+)            = e.dbid
        and b.instance_number(+) = e.instance_number
        and b.old_hash_value(+)  = e.old_hash_value
        and b.address(+)         = e.address
        and b.text_subset(+)     = e.text_subset
        and e.snap_id            = :eid
        and e.dbid               = :dbid
        and e.instance_number    = :inst_num
        and e.old_hash_value     = st.old_hash_value 
        and e.text_subset        = st.text_subset
        and st.piece            <= &&num_rows_per_hash
        and e.executions         > nvl(b.executions,0)
        and   decode(:dbcpu, 0, 2, null, 2, 100*(e.cpu_time - nvl(b.cpu_time,0))/:dbcpu)
            > decode(:dbcpu, 0, 1, null, 2, &&top_pct_sql) 
      order by (e.cpu_time - nvl(b.cpu_time,0)) desc, e.old_hash_value, st.piece
      )
where rownum < &&top_n_sql;



--  SQL statements ordered by Elapsed

ttitle lef 'SQL ordered by Elapsed  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
           '-> Resources reported for PL/SQL code includes the ' -
           'resources used by all SQL' -
       skip 1 -
           '   statements called by the code.' -
       skip 1 -
           '-> Total DB Time (s): ' format 99,999,999,999 dbtim_s -
       skip 1 -
           '-> Captured SQL accounts for ' format 990.9 elacappct '% of Total DB Time' -
       skip 1 -
           '-> SQL reported below exceeded  &top_pct_sql.% of Total DB Time' -
       skip 2;

-- Bug 1313544 requires this rather bizarre SQL statement

set underline off;
col aa format a80 heading -
'  Elapsed                Elap per            CPU                        Old|  Time (s)   Executions  Exec (s)  %Total   Time (s)  Physical Reads Hash Value |---------- ------------ ---------- ------ ---------- --------------- ----------' 

column hv noprint;
break on hv skip 1;

select aa, hv
  from ( select /*+ ordered use_nl (b st) */
          decode( st.piece
                , 0
                , lpad(  nvl(to_char(  (e.elapsed_time - nvl(b.elapsed_time,0))/1000000
                                   , '999990.00')
                       , ' '),10) || ' ' ||
                  lpad(to_char((e.executions - nvl(b.executions,0))
                              ,'999,999,999')
                      ,12)||' '||
                  lpad((to_char(decode(e.executions - nvl(b.executions,0)
                                      ,0, to_number(null)
                                      ,  ( (e.elapsed_time - nvl(b.elapsed_time,0))
                                          /(e.executions - nvl(b.executions,0))
                                         ) / 1000000
                                      )
                               , '999990.00'))
                      , 10) || ' ' ||
                  lpad( decode( :dbtim, 0, ' '
                              , to_char((100*(e.elapsed_time - nvl(b.elapsed_time,0))/:dbtim), '990.0')
                              )
                      , 6) ||' '||
                  lpad(  nvl(to_char(  (e.cpu_time - nvl(b.cpu_time,0))/1000000
                                   , '999990.00')
                       , ' '),10) || ' ' ||
                  lpad(to_char((e.disk_reads - nvl(b.disk_reads,0))
                               ,'99,999,999,999')
                      ,15)||' '||
                  lpad(e.old_hash_value,10)||' '||
                  decode(e.module,null,st.sql_text
                                      ,rpad('Module: '||e.module,80)||st.sql_text)
                , st.sql_text) aa
          , e.old_hash_value hv
       from stats$sql_summary e
          , stats$sql_summary b
          , stats$sqltext     st 
      where b.snap_id(+)         = :bid
        and b.dbid(+)            = e.dbid
        and b.instance_number(+) = e.instance_number
        and b.old_hash_value(+)  = e.old_hash_value
        and b.address(+)         = e.address
        and b.text_subset(+)     = e.text_subset
        and e.snap_id            = :eid
        and e.dbid               = :dbid
        and e.instance_number    = :inst_num
        and e.old_hash_value     = st.old_hash_value 
        and e.text_subset        = st.text_subset
        and st.piece            <= &&num_rows_per_hash
        and e.executions         > nvl(b.executions,0)
        and    decode(:dbtim, 0, 2, 100*(e.elapsed_time - nvl(b.elapsed_time,0))/:dbtim)
             > decode(:dbtim, 0, 1, &&top_pct_sql)
      order by (e.elapsed_time - nvl(b.elapsed_time,0)) desc, e.old_hash_value, st.piece
      )
where rownum < &&top_n_sql;


--
--  SQL statements ordered by Gets

ttitle lef 'SQL ordered by Gets  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
           '-> Resources reported for PL/SQL code includes the ' -
           'resources used by all SQL' -
       skip 1 -
           '   statements called by the code.' -
       skip 1 -
           '-> End Buffer Gets Threshold: '   ebgt ' Total Buffer Gets: ' format 99,999,999,999 getsa -
       skip 1 -
           '-> Captured SQL accounts for ' format 990.9 bufcappct '% of Total Buffer Gets' -
       skip 1 -
           '-> SQL reported below exceeded  &top_pct_sql.% of Total Buffer Gets' -
       skip 2;

-- Bug 1313544 requires this rather bizarre SQL statement

set underline off;
col aa format a80 heading -
'                                                     CPU      Elapsd     Old|  Buffer Gets    Executions  Gets per Exec  %Total Time (s)  Time (s) Hash Value |--------------- ------------ -------------- ------ -------- --------- ----------' 

column hv noprint;
break on hv skip 1;

select aa, hv
  from ( select /*+ ordered use_nl (b st) */
          decode( st.piece
                , 0
                , lpad(to_char((e.buffer_gets - nvl(b.buffer_gets,0))
                               ,'99,999,999,999')
                      ,15)||' '||
                  lpad(to_char((e.executions - nvl(b.executions,0))
                              ,'999,999,999')
                      ,12)||' '||
                  lpad((to_char(decode(e.executions - nvl(b.executions,0)
                                     ,0, to_number(null)
                                     ,(e.buffer_gets - nvl(b.buffer_gets,0)) /
                                      (e.executions - nvl(b.executions,0)))
                               ,'999,999,990.0'))
                      ,14) ||' '||
                  lpad((to_char(100*(e.buffer_gets - nvl(b.buffer_gets,0))/:slr
                               ,'990.0'))
                      , 6) ||' '||
                  lpad(  nvl(to_char(  (e.cpu_time - nvl(b.cpu_time,0))/1000000
                                   , '9990.00')
                       , ' '),8) || ' ' ||
                  lpad(  nvl(to_char(  (e.elapsed_time - nvl(b.elapsed_time,0))/1000000
                                   , '99990.00')
                       , ' '),9) || ' ' ||
                  lpad(e.old_hash_value,10)||''||
                  decode(e.module,null,st.sql_text
                                      ,rpad('Module: '||e.module,80)||st.sql_text)
                , st.sql_text) aa
          , e.old_hash_value hv
       from stats$sql_summary e
          , stats$sql_summary b
          , stats$sqltext     st 
      where b.snap_id(+)         = :bid
        and b.dbid(+)            = e.dbid
        and b.instance_number(+) = e.instance_number
        and b.old_hash_value(+)  = e.old_hash_value
        and b.address(+)         = e.address
        and b.text_subset(+)     = e.text_subset
        and e.snap_id            = :eid
        and e.dbid               = :dbid
        and e.instance_number    = :inst_num
        and e.old_hash_value     = st.old_hash_value 
        and e.text_subset        = st.text_subset
        and st.piece            <= &&num_rows_per_hash
        and e.executions         > nvl(b.executions,0)
        and 100*(e.buffer_gets - nvl(b.buffer_gets,0))/:slr > &&top_pct_sql
      order by (e.buffer_gets - nvl(b.buffer_gets,0)) desc, e.old_hash_value, st.piece
      )
where rownum < &&top_n_sql;


--
--  SQL statements ordered by physical reads

ttitle lef 'SQL ordered by Reads  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
           '-> End Disk Reads Threshold: '   edrt '  Total Disk Reads: ' format 99,999,999,999 phyra -
       skip 1 -
           '-> Captured SQL accounts for ' format 990.9 phycappct '% of Total Disk Reads' -
       skip 1 -
           '-> SQL reported below exceeded  &top_pct_sql.% of Total Disk Reads' -
       skip 2;

col aa format a80 heading -
'                                                     CPU      Elapsd     Old| Physical Reads  Executions  Reads per Exec %Total Time (s)  Time (s) Hash Value |--------------- ------------ -------------- ------ -------- --------- ----------' 

select aa, hv
  from ( select /*+ ordered use_nl (b st) */
          decode( st.piece
                , 0
                , lpad(to_char((e.disk_reads - nvl(b.disk_reads,0))
                               ,'99,999,999,999')
                      ,15)||' '||
                  lpad(to_char((e.executions - nvl(b.executions,0))
                              ,'999,999,999')
                      ,12)||' '||
                  lpad((to_char(decode(e.executions - nvl(b.executions,0)
                                     ,0, to_number(null)
                                     ,(e.disk_reads - nvl(b.disk_reads,0)) /
                                      (e.executions - nvl(b.executions,0)))
                               ,'999,999,990.0'))
                      ,14) ||' '||
                  lpad((to_char(100*(e.disk_reads - nvl(b.disk_reads,0))/:phyr
                               ,'990.0'))
                      , 6) ||' '||
                  lpad(  nvl(to_char(  (e.cpu_time - nvl(b.cpu_time,0))/1000000
                                   , '9990.00')
                       , ' '),8) || ' ' ||
                  lpad(  nvl(to_char(  (e.elapsed_time - nvl(b.elapsed_time,0))/1000000
                                   , '99990.00')
                       , ' '),9) || ' ' ||
                  lpad(e.old_hash_value,10)||''||
                  decode(e.module,null,st.sql_text
                                      ,rpad('Module: '||e.module,80)||st.sql_text)
                , st.sql_text) aa
          , e.old_hash_value hv
       from stats$sql_summary e
          , stats$sql_summary b
          , stats$sqltext     st 
      where b.snap_id(+)         = :bid
        and b.dbid(+)            = e.dbid
        and b.instance_number(+) = e.instance_number
        and b.old_hash_value(+)  = e.old_hash_value
        and b.address(+)         = e.address
        and b.text_subset(+)     = e.text_subset
        and e.snap_id            = :eid
        and e.dbid               = :dbid
        and e.instance_number    = :inst_num
        and e.old_hash_value     = st.old_hash_value 
        and e.text_subset        = st.text_subset
        and st.piece            <= &&num_rows_per_hash
        and e.executions         > nvl(b.executions,0)
        and :phyr                > 0
        and 100*(e.disk_reads - nvl(b.disk_reads,0))/:phyr > &&top_pct_sql
      order by (e.disk_reads - nvl(b.disk_reads,0)) desc, e.old_hash_value, st.piece
      )
where rownum < &&top_n_sql;



--
--  SQL statements ordered by executions

ttitle lef 'SQL ordered by Executions  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
           '-> End Executions Threshold: '   eet '  Total Executions: ' format 99,999,999,999 exea-
       skip 1 -
           '-> Captured SQL accounts for ' format 990.9 execappct '% of Total Executions' -
       skip 1 -
           '-> SQL reported below exceeded  &top_pct_sql.% of Total Executions' -
       skip 2;

col aa format a80 heading -
'                                                CPU per    Elap per     Old| Executions   Rows Processed   Rows per Exec    Exec (s)   Exec (s)  Hash Value |------------ --------------- ---------------- ----------- ---------- ----------' 

select aa, hv
  from ( select /*+ ordered use_nl (b st) */
          decode( st.piece
                , 0
                , lpad(to_char((e.executions - nvl(b.executions,0))
                               ,'999,999,999')
                      ,12)||' '||
                  lpad(to_char((nvl(e.rows_processed,0) - nvl(b.rows_processed,0))
                              ,'99,999,999,999')
                      ,15)||' '||
                  lpad((to_char(decode(nvl(e.rows_processed,0) - nvl(b.rows_processed,0)
                                     ,0, 0
                                     ,(e.rows_processed - nvl(b.rows_processed,0)) /
                                      (e.executions - nvl(b.executions,0)))
                               ,'9,999,999,990.0'))
                      ,16) ||' '||
                  lpad(nvl(to_char(   (e.cpu_time   - nvl(b.cpu_time,0))
                                     /(e.executions - nvl(b.executions,0))
                                   /1000000
                               , '999990.00'),' '),10) || ' ' ||
                  lpad(nvl(to_char(   (e.elapsed_time - nvl(b.elapsed_time,0))
                                 /(e.executions   - nvl(b.executions,0))
                                 /1000000
                               , '9999990.00'),' '),11) || ' ' ||
                  lpad(e.old_hash_value,10)||' '||
                  decode(e.module,null,st.sql_text
                                      ,rpad('Module: '||e.module,80)||st.sql_text)
                , st.sql_text) aa
          , e.old_hash_value hv
       from stats$sql_summary e
          , stats$sql_summary b
          , stats$sqltext     st 
      where b.snap_id(+)         = :bid
        and b.dbid(+)            = e.dbid
        and b.instance_number(+) = e.instance_number
        and b.old_hash_value(+)  = e.old_hash_value
        and b.address(+)         = e.address
        and b.text_subset(+)     = e.text_subset
        and e.snap_id            = :eid
        and e.dbid               = :dbid
        and e.instance_number    = :inst_num
        and e.old_hash_value     = st.old_hash_value 
        and e.text_subset        = st.text_subset
        and st.piece            <= &&num_rows_per_hash
        and e.executions         > nvl(b.executions,0)
        and 100*(e.executions - nvl(b.executions,0))/:exe > &&top_pct_sql
      order by (e.executions - nvl(b.executions,0)) desc, e.old_hash_value, st.piece
      )
where rownum < &&top_n_sql;



--
--  SQL statements ordered by Parse Calls

ttitle lef 'SQL ordered by Parse Calls  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
           '-> End Parse Calls Threshold: ' epc ' Total Parse Calls: ' format 99,999,999,999 prsea -
       skip 1 -
           '-> Captured SQL accounts for ' format 990.9 prscappct '% of Total Parse Calls' -
       skip 1 -
           '-> SQL reported below exceeded  &top_pct_sql.% of Total Parse Calls' -
       skip 2;


col aa format a80 heading -
'                           % Total    Old| Parse Calls  Executions   Parses  Hash Value |------------ ------------ -------- ----------' 
column hv noprint;
break on hv skip 1;

select aa, hv
  from ( select /*+ ordered use_nl (b st) */
          decode( st.piece
                , 0
                , lpad(to_char((e.parse_calls - nvl(b.parse_calls,0))
                               ,'999,999,999')
                      ,12)||' '||
                  lpad(to_char((e.executions - nvl(b.executions,0))
                              ,'999,999,999')
                      ,12)||' '||
                  lpad(to_char(100*(e.parse_calls - nvl(b.parse_calls,0))/:prse
                               ,'990.09')
                      ,8)||' '||
                  lpad(e.old_hash_value,10)||' '||
                  rpad(' ',34)||
                  decode(e.module,null,st.sql_text
                                      ,rpad('Module: '||e.module,80)||st.sql_text)
                , st.sql_text) aa
          , e.old_hash_value hv
       from stats$sql_summary e
          , stats$sql_summary b
          , stats$sqltext     st 
      where b.snap_id(+)         = :bid
        and b.dbid(+)            = e.dbid
        and b.instance_number(+) = e.instance_number
        and b.old_hash_value(+)  = e.old_hash_value
        and b.address(+)         = e.address
        and b.text_subset(+)     = e.text_subset
        and e.snap_id            = :eid
        and e.dbid               = :dbid
        and e.instance_number    = :inst_num
        and e.old_hash_value     = st.old_hash_value 
        and e.text_subset        = st.text_subset
        and st.piece            <= &&num_rows_per_hash
        and 100*(e.parse_calls - nvl(b.parse_calls,0))/:prse > &&top_pct_sql
      order by (e.parse_calls - nvl(b.parse_calls,0)) desc, e.old_hash_value, st.piece
      )
where rownum < &&top_n_sql;



--
--  SQL statements ordered by Sharable Memory

ttitle lef 'SQL ordered by Sharable Memory  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
           '-> End Sharable Memory Threshold: ' format 99999999 esmt -
       skip 2;

col aa format a80 heading -
'Sharable Mem (b)  Executions  % Total Old Hash Value |---------------- ------------ ------- --------------' 

select aa, hv
  from ( select /*+ ordered use_nl (b st) */
          decode( st.piece
                , 0
                , lpad(to_char( e.sharable_mem
                               ,'999,999,999,999')
                      ,16)||' '||
                  lpad(to_char((e.executions - nvl(b.executions,0))
                              ,'999,999,999')
                      ,12)||' '||
                  lpad((to_char(100*e.sharable_mem/:espm
                               ,'990.0'))
                      , 7) ||' '||
                  lpad(e.old_hash_value,12)||' '||
                  rpad(' ',29)||
                  decode(e.module,null,st.sql_text
                                      ,rpad('Module: '||e.module,80)||st.sql_text)
                , st.sql_text) aa
          , e.old_hash_value hv
       from stats$sql_summary e
          , stats$sql_summary b
          , stats$sqltext     st 
      where b.snap_id(+)         = :bid
        and b.dbid(+)            = e.dbid
        and b.instance_number(+) = e.instance_number
        and b.old_hash_value(+)  = e.old_hash_value
        and b.address(+)         = e.address
        and b.text_subset(+)     = e.text_subset
        and e.snap_id            = :eid
        and e.dbid               = :dbid
        and e.instance_number    = :inst_num
        and e.old_hash_value     = st.old_hash_value 
        and e.text_subset        = st.text_subset
        and st.piece            <= &&num_rows_per_hash
        and e.executions         > nvl(b.executions,0)
        and e.sharable_mem       > :esmt
      order by e.sharable_mem desc, e.old_hash_value, st.piece
      )
where rownum < &&top_n_sql;



--
--  SQL statements ordered by Version Count

ttitle lef 'SQL ordered by Version Count  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
           '-> End Version Count Threshold: ' format 99999999 evc -
       skip 2;

col aa format a80 heading -
' Version|   Count  Executions   Old Hash Value |-------- ------------ ---------------' 

select aa, hv
  from ( select /*+ ordered use_nl (b st) */
          decode( st.piece
                , 0
                , lpad(to_char( e.version_count
                               ,'999,999')
                      ,8)||' '||
                  lpad(to_char((e.executions - nvl(b.executions,0))
                              ,'999,999,999')
                      ,12)||' '||
                  lpad(e.old_hash_value,12)||' '||
                  rpad(' ',45)||
                  decode(e.module,null,st.sql_text
                                      ,rpad('Module: '||e.module,80)||st.sql_text)
                , st.sql_text) aa
          , e.old_hash_value hv
       from stats$sql_summary e
          , stats$sql_summary b
          , stats$sqltext     st 
      where b.snap_id(+)         = :bid
        and b.dbid(+)            = e.dbid
        and b.instance_number(+) = e.instance_number
        and b.old_hash_value(+)  = e.old_hash_value
        and b.address(+)         = e.address
        and b.text_subset(+)     = e.text_subset
        and e.snap_id            = :eid
        and e.dbid               = :dbid
        and e.instance_number    = :inst_num
        and e.old_hash_value     = st.old_hash_value 
        and e.text_subset        = st.text_subset
        and st.piece            <= &&num_rows_per_hash
        and e.executions         > nvl(b.executions,0)
        and e.version_count      > :evc
      order by e.version_count desc, e.old_hash_value, st.piece
      )
where rownum < &&top_n_sql;


--
--  SQL statements ordered by Cluster Wait Time
--

ttitle lef 'SQL ordered by Cluster Wait Time  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 2;

col aa format a80 heading -
'  Cluster      CWT % of     Elapsd        CPU                      Old|Wait Time (s) Elapsd Time   Time (s)    Time (s)    Executions   Hash Value |------------- ----------- ----------- ----------- -------------- ----------' 

select aa, hv
  from ( select /*+ ordered use_nl (b st) */
          decode( st.piece
                , 0
                , lpad(  nvl(to_char((e.cluster_wait_time - nvl(b.cluster_wait_time,0))/1000000
                                    ,'9,999,999.00')
                      , ' '),13) || ' ' ||
                  lpad(  nvl(to_char(100*(e.cluster_wait_time - nvl(b.cluster_wait_time,0))
                                        /(e.elapsed_time      - nvl(b.elapsed_time,0))
                                    ,'990.0')
                      , ' '),11) || ' ' ||
                  lpad(  nvl(to_char((e.elapsed_time - nvl(b.elapsed_time,0))/1000000
                                    ,'999,990.00')
                      , ' '),11) || ' ' ||
                  lpad(  nvl(to_char((e.cpu_time - nvl(b.cpu_time,0))/1000000
                                    ,'999,990.00')
                      , ' '),11) || ' ' ||
                  lpad(      to_char((e.executions - nvl(b.executions,0))
                                    ,'9,999,999,999')
                            ,14) || ' ' ||
                  lpad(e.old_hash_value,10)||''||
                  rpad (' ',5)||
                  decode(e.module,null,st.sql_text
                                      ,rpad('Module: '||e.module,80)||st.sql_text)
                , st.sql_text) aa
          , e.old_hash_value hv
       from stats$sql_summary e
          , stats$sql_summary b
          , stats$sqltext     st 
      where b.snap_id(+)         = :bid
        and b.dbid(+)            = e.dbid
        and b.instance_number(+) = e.instance_number
        and b.old_hash_value(+)  = e.old_hash_value
        and b.address(+)         = e.address
        and b.text_subset(+)     = e.text_subset
        and e.snap_id            = :eid
        and e.dbid               = :dbid
        and e.instance_number    = :inst_num
        and e.old_hash_value     = st.old_hash_value 
        and e.text_subset        = st.text_subset
        and st.piece            <= &&num_rows_per_hash
        and e.cluster_wait_time  > nvl(b.cluster_wait_time,0)
      order by (e.cluster_wait_time - nvl(b.cluster_wait_time,0)) desc, e.old_hash_value, st.piece
      )
where rownum < &&top_n_sql
  and :para = 'YES';

set underline '-';



--
--  Instance Activity Statistics

ttitle lef 'Instance Activity Stats  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 2;

column st  format a33                  heading 'Statistic' trunc;
column dif format 9,999,999,999,990    heading 'Total';
column ps  format       999,999,990.9  heading 'per Second';
column pt  format         9,999,990.9  heading 'per Trans';

select b.name                             st
     , e.value - b.value                  dif
     , round((e.value - b.value)/:ela,2)  ps
     , round((e.value - b.value)/:tran,2) pt
 from  stats$sysstat b
     , stats$sysstat e
 where b.snap_id         = :bid
   and e.snap_id         = :eid
   and b.dbid            = :dbid
   and e.dbid            = :dbid
   and b.instance_number = :inst_num
   and e.instance_number = :inst_num
   and b.name            = e.name
   and e.name not in (  'logons current'
                      , 'opened cursors current'
                      , 'workarea memory allocated'
                      , 'session cursor cache count'
                     )
   and e.value          >= b.value
   and e.value          >  0
 order by st;



--
--  Instance Activity Statistics - absolute values

set newpage 1;

ttitle lef 'Instance Activity Stats  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
       lef '-> Statistics with absolute values (should not be diffed)' -
       skip 2;

column begin_value format 99,999,999,999 heading 'Begin Value'
column end_value   format 99,999,999,999 heading 'End Value'

select b.name        st
     , b.value       begin_value
     , e.value       end_value
 from  stats$sysstat b
     , stats$sysstat e
 where b.snap_id         = :bid
   and e.snap_id         = :eid
   and b.dbid            = :dbid
   and e.dbid            = :dbid
   and b.instance_number = :inst_num
   and e.instance_number = :inst_num
   and b.name            = e.name
   and e.name          in (  'logons current'
                           , 'opened cursors current'
                           , 'workarea memory allocated'
                           , 'session cursor cache count'
                          )
   and (   b.value > 0 
        or e.value > 0
       );

set newpage 0;


--
--  Non-sysstat Instance Activity Statistics

set newpage 1;

ttitle lef 'Instance Activity Stats  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
       lef '-> Statistics identified by ''(derived)'' come from sources other than SYSSTAT' -
       skip 2;

column ph format 9,999.99  heading 'per Hour';
select 'log switches (derived)'                st
     , e.sequence# - b.sequence#               dif
     , (e.sequence# - b.sequence#)/(:ela/3600) ph
  from stats$thread e
     , stats$thread b
 where b.snap_id                = :bid
   and e.snap_id                = :eid
   and b.dbid                   = :dbid
   and e.dbid                   = :dbid
   and b.instance_number        = :inst_num
   and e.instance_number        = :inst_num
   and b.thread#                = e.thread#
   and b.thread_instance_number = e.thread_instance_number
   and e.thread_instance_number = :inst_num;

set newpage 0;


--
--  OS Stat

set newpage 1;

ttitle lef 'OS Statistics  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
       lef '-> ordered by statistic type (CPU use, Virtual Memory, Hardware Config), Name' -
       skip 2;

column osn  format    a25                  heading 'Statistic' trunc;
column dif  format  9,999,999,999,999,990  heading 'Total';
column ps   format      9,999,999,999,990  heading 'per Second';
column styp noprint

select osn.stat_name                                              osn
     , decode( osn.osstat_id
             , 0,    e.value    -- NUM_CPUS
             , 15,   e.value    -- LOAD
             , 16,   e.value    -- NUM_CPU_CORES
             , 17,   e.value    -- NUM_CPU_SOCKETS
             , 1008, e.value    -- PHYSICAL_MEMORY_BYTES
             , e.value - b.value)                                 dif
     , (  to_number(decode(sign(instrb(osn.stat_name, 'TIME')),            1, 1, 0))
        + to_number(decode(sign(instrb(osn.stat_name, 'LOAD')),            1, 2, 0))
        + to_number(decode(sign(instrb(osn.stat_name, 'CPU_WAIT')),        1, 3, 0))
        + to_number(decode(sign(instrb(osn.stat_name, 'VM_')),             1, 4, 0))
        + to_number(decode(sign(instrb(osn.stat_name, 'PHYSICAL_MEMORY')), 1, 5, 0))
        + to_number(decode(sign(instrb(osn.stat_name, 'NUM_CPU')),         1, 6, 0))
       )                                                          styp
 from  stats$osstat b
     , stats$osstat e
     , stats$osstatname osn
 where b.snap_id         = :bid
   and e.snap_id         = :eid
   and b.dbid            = :dbid
   and e.dbid            = :dbid
   and b.instance_number = :inst_num
   and e.instance_number = :inst_num
   and b.osstat_id       = e.osstat_id
   and osn.osstat_id     = e.osstat_id
   and osn.stat_name not like 'AVG_%'
   and e.value          >= b.value
   and e.value          >  0
 order by styp, osn;

set newpage 0;


--
--  Session Wait Events

ttitle lef 'Session Wait Events  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
       lef 'Session Id: ' sess_id '  Serial#: ' serial -
       skip 1 -
       lef '-> ordered by wait time desc, waits desc (idle events last)' -
       skip 2;

col event    format a28         heading 'Event' trunc;

-- fix for bug 5145816
select e.event 
     , e.total_waits - nvl(b.total_waits,0)       waits 
     , e.total_timeouts - nvl(b.total_timeouts,0) timeouts 
     , (e.time_waited_micro - nvl(b.time_waited_micro,0))/1000000  time 
     , decode ((e.total_waits - nvl(b.total_waits, 0)), 
                0, to_number(NULL), 
                  ((e.time_waited_micro - nvl(b.time_waited_micro,0))/1000) 
                 / (e.total_waits - nvl(b.total_waits,0)) )        wt 
     , (e.total_waits - nvl(b.total_waits,0))/:tran txwaits 
     , decode(i.event, null, 0, 99)               idle 
from stats$session_event b 
     , stats$session_event e 
     , stats$idle_event    i 
     , stats$snapshot      bs 
     , stats$snapshot      es 
where b.snap_id(+)             = :bid 
   and e.snap_id             = :eid 
   and b.dbid(+)                = :dbid 
   and e.dbid                = :dbid 
   and b.instance_number(+)     = :inst_num 
   and e.instance_number     = :inst_num 
   and b.event(+)               = e.event 
   and e.total_waits         > nvl(b.total_waits,0) 
   and i.event(+)            = e.event 
   and bs.snap_id            = :bid 
   and es.snap_id            = :eid 
   and bs.dbid               = :dbid 
   and es.dbid               = :dbid 
   and bs.instance_number    = :inst_num 
   and es.instance_number    = :inst_num 
   and bs.session_id         = es.session_id 
   and bs.serial#            = es.serial# 
order by idle, time desc, waits desc; 



--
--  Session Time Model Statistics

ttitle lef 'Session Time Model Stats  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
       lef 'Session Id: ' sess_id '  Serial#: ' serial -
       skip 1 -
       lef '-> Total Time in Database calls  &DBtimes.s (or &DBtime.us)' -
       skip 1 -
       lef '-> Ordered by % of DB time desc, Statistic name' -
       skip 2;

column statnam format a35 trunc              heading 'Statistic'
column tdifs   format 9,999,999,999,990.9    heading 'Time (s)'
column pctdb   format 99999.9                heading '% of DB time'
column order_col noprint

select statnam
     , tdif/&ustos                        tdifs
     , decode(order_col, 0, 100*tdif/&DBtime
                       , to_number(null)
             )                            pctdb
     , order_col
  from (select sn.stat_name               statnam
             , (e.value - b.value)        tdif
             , decode( sn.stat_name
                     , 'DB time',                 1
                     , 'background cpu time',     2
                     , 'background elapsed time', 2
                     , 0
                     )                    order_col
          from stats$sess_time_model e
             , stats$sess_time_model b
             , stats$time_model_statname sn
         where b.snap_id                = :bid
           and e.snap_id                = :eid
           and b.dbid                   = :dbid
           and e.dbid                   = :dbid
           and b.instance_number        = :inst_num
           and e.instance_number        = :inst_num
           and b.stat_id                = e.stat_id
           and sn.stat_id               = e.stat_id
           and e.value - b.value        > 0
       )
 order by order_col, decode(pctdb, null, tdifs, pctdb) desc;


--
--  Session Statistics

ttitle lef 'Session Statistics  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
       lef 'Session Id: ' sess_id '  Serial#: ' serial -
       skip 2;

column dif format 9,999,999,999,990    heading 'Total';

select lower(substr(ss.name,1,38)) st
     , to_number(decode(instr(ss.name,'current')
                     ,0,e.value - b.value,null)) dif
     , to_number(decode(instr(ss.name,'current')
                       ,0,round((e.value - b.value)
                                        /:ela,2),null)) ps
     , to_number(decode(instr(ss.name,'current')
                       ,0,decode(:strn, 
                                 0, round(e.value - b.value), 
                                    round((e.value - b.value)
                                     /:strn,2),null))) pt
  from stats$sesstat b
     , stats$sesstat e
     , stats$sysstat ss
     , stats$snapshot bs
     , stats$snapshot es
 where b.snap_id          = :bid
   and e.snap_id          = :eid
   and b.dbid             = :dbid
   and e.dbid             = :dbid
   and b.instance_number  = :inst_num
   and e.instance_number  = :inst_num
   and ss.snap_id         = :eid
   and ss.dbid            = :dbid
   and ss.instance_number = :inst_num
   and b.statistic#       = e.statistic#
   and ss.statistic#      = e.statistic#
   and e.value            > b.value
   and bs.snap_id         = b.snap_id
   and es.snap_id         = e.snap_id
   and bs.dbid            = b.dbid
   and es.dbid            = b.dbid
   and bs.dbid            = e.dbid
   and es.dbid            = e.dbid
   and bs.dbid            = ss.dbid
   and es.dbid            = ss.dbid
   and bs.instance_number = b.instance_number
   and es.instance_number = b.instance_number
   and bs.instance_number = ss.instance_number
   and es.instance_number = ss.instance_number
   and bs.instance_number = e.instance_number
   and es.instance_number = e.instance_number
   and bs.session_id      = es.session_id
   and bs.serial#         = es.serial#
 order by st;



--
--  Tablespace IO summary statistics

ttitle lef 'Tablespace IO Stats  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
       lef '->ordered by IOs (Reads + Writes) desc' -
       skip 2;

col tsname     format a30           heading 'Tablespace';
col reads      format 9,999,999,990 heading 'Reads' newline;
col atpr       format 990.0         heading 'Av|Rd(ms)'     just c;
col writes     format 999,999,990   heading 'Writes';
col waits      format 9,999,990     heading 'Buffer|Waits'
col atpwt      format 990.0         heading 'Av Buf|Wt(ms)' just c;
col rps        format 99,999        heading 'Av|Reads/s'    just c;
col wps        format 99,999        heading 'Av|Writes/s'   just c;
col bpr        format 999.0         heading 'Av|Blks/Rd'    just c;
col ios        noprint

select e.tsname
     , sum (e.phyrds - nvl(b.phyrds,0))                     reads
     , sum (e.phyrds - nvl(b.phyrds,0))/:ela                rps
     , decode( sum(e.phyrds - nvl(b.phyrds,0))
             , 0, 0
             , (sum(e.readtim - nvl(b.readtim,0)) /
                sum(e.phyrds  - nvl(b.phyrds,0)))*10)       atpr
     , decode( sum(e.phyrds - nvl(b.phyrds,0))
             , 0, to_number(NULL)
             , sum(e.phyblkrd - nvl(b.phyblkrd,0)) / 
               sum(e.phyrds   - nvl(b.phyrds,0)) )          bpr
     , sum (e.phywrts    - nvl(b.phywrts,0))                writes
     , sum (e.phywrts    - nvl(b.phywrts,0))/:ela           wps
     , sum (e.wait_count - nvl(b.wait_count,0))             waits
     , decode (sum(e.wait_count - nvl(b.wait_count, 0))
            , 0, 0
            , (sum(e.time       - nvl(b.time,0)) / 
               sum(e.wait_count - nvl(b.wait_count,0)))*10) atpwt
     , sum (e.phyrds  - nvl(b.phyrds,0))  +  
       sum (e.phywrts - nvl(b.phywrts,0))                   ios
  from stats$filestatxs e
     , stats$filestatxs b
 where b.snap_id(+)         = :bid
   and e.snap_id            = :eid
   and b.dbid(+)            = :dbid
   and e.dbid               = :dbid
   and b.dbid(+)            = e.dbid
   and b.instance_number(+) = :inst_num
   and e.instance_number    = :inst_num
   and b.instance_number(+) = e.instance_number
   and b.tsname(+)          = e.tsname
   and b.filename(+)        = e.filename
   and ( (e.phyrds  - nvl(b.phyrds,0)  )  + 
         (e.phywrts - nvl(b.phywrts,0) ) ) > 0
 group by e.tsname
union all
select e.tsname                                             tbsp
     , sum (e.phyrds - nvl(b.phyrds,0))                     reads
     , sum (e.phyrds - nvl(b.phyrds,0))/:ela                rps
     , decode( sum(e.phyrds - nvl(b.phyrds,0))
             , 0, 0
             , (sum(e.readtim - nvl(b.readtim,0)) /
                sum(e.phyrds  - nvl(b.phyrds,0)))*10)       atpr
     , decode( sum(e.phyrds - nvl(b.phyrds,0))
             , 0, to_number(NULL)
             , sum(e.phyblkrd - nvl(b.phyblkrd,0)) / 
               sum(e.phyrds   - nvl(b.phyrds,0)) )          bpr
     , sum (e.phywrts    - nvl(b.phywrts,0))                writes
     , sum (e.phywrts    - nvl(b.phywrts,0))/:ela           wps
     , sum (e.wait_count - nvl(b.wait_count,0))             waits
     , decode (sum(e.wait_count - nvl(b.wait_count, 0))
            , 0, 0
            , (sum(e.time       - nvl(b.time,0)) / 
               sum(e.wait_count - nvl(b.wait_count,0)))*10) atpwt
     , sum (e.phyrds  - nvl(b.phyrds,0))  +  
       sum (e.phywrts - nvl(b.phywrts,0))                   ios
  from stats$tempstatxs e
     , stats$tempstatxs b
 where b.snap_id(+)         = :bid
   and e.snap_id            = :eid
   and b.dbid(+)            = :dbid
   and e.dbid               = :dbid
   and b.dbid(+)            = e.dbid
   and b.instance_number(+) = :inst_num
   and e.instance_number    = :inst_num
   and b.instance_number(+) = e.instance_number
   and b.tsname(+)          = e.tsname
   and b.filename(+)        = e.filename
   and ( (e.phyrds  - nvl(b.phyrds,0)  )  + 
         (e.phywrts - nvl(b.phywrts,0) ) ) > 0
 group by e.tsname
 order by ios desc;



--
--  File IO statistics

ttitle lef 'File IO Stats  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
       lef '->Mx Rd Bkt: Max bucket time for single block read' -
       skip 1 -
       lef '->ordered by Tablespace, File' -
       skip 2;

col tsname     format a24           heading 'Tablespace' trunc;
col filename   format a52           heading 'Filename'   trunc;
col reads      format 9,999,999,990 heading 'Reads'
col atpwt      format 990.0         heading 'Av|BufWt|(ms)' just c;
col atpr       format 90.0          heading 'Av|Rd|(ms)'    just c;
col mrt        format 99            heading 'Mx|Rd|Bkt'     just c;
break on tsname skip 1;

select e.tsname
     , e.filename
     , e.phyrds- nvl(b.phyrds,0)                       reads
     , (e.phyrds- nvl(b.phyrds,0))/:ela                rps
     , decode ((e.phyrds - nvl(b.phyrds, 0)), 0, to_number(NULL),
          ((e.readtim  - nvl(b.readtim,0)) /
           (e.phyrds   - nvl(b.phyrds,0)))*10)         atpr
     , max_read.mrt
     , decode ((e.phyrds - nvl(b.phyrds, 0)), 0, to_number(NULL),
          (e.phyblkrd - nvl(b.phyblkrd,0)) / 
          (e.phyrds   - nvl(b.phyrds,0)) )             bpr
     , e.phywrts - nvl(b.phywrts,0)                    writes
     , (e.phywrts - nvl(b.phywrts,0))/:ela             wps
     , e.wait_count - nvl(b.wait_count,0)              waits
     , decode ((e.wait_count - nvl(b.wait_count, 0)), 0, to_number(NULL),
          ((e.time       - nvl(b.time,0)) /
           (e.wait_count - nvl(b.wait_count,0)))*10)   atpwt
  from stats$filestatxs e
     , stats$filestatxs b
     , (select max(e.singleblkrdtim_milli) mrt
             , e.file#                     fn
          from stats$file_histogram b
             , stats$file_histogram e
         where b.snap_id(+)         = :bid
           and e.snap_id            = :eid
           and b.dbid(+)            = :dbid
           and e.dbid               = :dbid
           and b.dbid(+)            = e.dbid
           and b.instance_number(+) = :inst_num
           and e.instance_number    = :inst_num
           and b.instance_number(+) = e.instance_number
           and b.file#(+)           = e.file#
           and b.singleblkrdtim_milli(+) = e.singleblkrdtim_milli
           and (e.singleblkrds - nvl(b.singleblkrds,0)) > 0
           and upper('&&display_file_io') = 'Y'
         group by e.file#
       ) max_read
 where b.snap_id(+)         = :bid
   and e.snap_id            = :eid
   and b.dbid(+)            = :dbid
   and e.dbid               = :dbid
   and b.dbid(+)            = e.dbid
   and b.instance_number(+) = :inst_num
   and e.instance_number    = :inst_num
   and b.instance_number(+) = e.instance_number
   and b.tsname(+)          = e.tsname
   and b.filename(+)        = e.filename
   and max_read.fn(+)       = e.file#
   and ( (e.phyrds  - nvl(b.phyrds,0)  ) + 
         (e.phywrts - nvl(b.phywrts,0) ) ) > 0
union all
select e.tsname
     , e.filename
     , e.phyrds- nvl(b.phyrds,0)                       reads
     , (e.phyrds- nvl(b.phyrds,0))/:ela                rps
     , decode ((e.phyrds - nvl(b.phyrds, 0)), 0, to_number(NULL),
          ((e.readtim  - nvl(b.readtim,0)) /
           (e.phyrds   - nvl(b.phyrds,0)))*10)         atpr
     , max_read.mrt
     , decode ((e.phyrds - nvl(b.phyrds, 0)), 0, to_number(NULL),
          (e.phyblkrd - nvl(b.phyblkrd,0)) / 
          (e.phyrds   - nvl(b.phyrds,0)) )             bpr
     , e.phywrts - nvl(b.phywrts,0)                    writes
     , (e.phywrts - nvl(b.phywrts,0))/:ela             wps
     , e.wait_count - nvl(b.wait_count,0)              waits
     , decode ((e.wait_count - nvl(b.wait_count, 0)), 0, to_number(NULL),
          ((e.time       - nvl(b.time,0)) /
           (e.wait_count - nvl(b.wait_count,0)))*10)   atpwt
  from stats$tempstatxs e
     , stats$tempstatxs b
     , (select max(e.singleblkrdtim_milli) mrt
             , e.file#                     fn
          from stats$temp_histogram b
             , stats$temp_histogram e
         where b.snap_id(+)         = :bid
           and e.snap_id            = :eid
           and b.dbid(+)            = :dbid
           and e.dbid               = :dbid
           and b.dbid(+)            = e.dbid
           and b.instance_number(+) = :inst_num
           and e.instance_number    = :inst_num
           and b.instance_number(+) = e.instance_number
           and b.file#(+)           = e.file#
           and b.singleblkrdtim_milli(+) = e.singleblkrdtim_milli
           and (e.singleblkrds - nvl(b.singleblkrds,0)) > 0
           and upper('&&display_file_io') = 'Y'
         group by e.file#
       ) max_read
 where b.snap_id(+)         = :bid
   and e.snap_id            = :eid
   and b.dbid(+)            = :dbid
   and e.dbid               = :dbid
   and b.dbid(+)            = e.dbid
   and b.instance_number(+) = :inst_num
   and e.instance_number    = :inst_num
   and b.instance_number(+) = e.instance_number
   and b.tsname(+)          = e.tsname 
   and b.filename(+)        = e.filename
   and max_read.fn(+)       = e.file#
   and ( (e.phyrds  - nvl(b.phyrds,0)  ) + 
         (e.phywrts - nvl(b.phywrts,0) ) ) > 0
 order by tsname, filename;



--
--  File IO Histogram statistics

ttitle lef 'File Read Histogram Stats  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
       lef '->Number of single block reads in each time range' -
       skip 1 -
       lef '->ordered by Tablespace, File' -
       skip 2;

col tsname   format a24           heading 'Tablespace' trunc;
col filename format a52           heading 'Filename'   trunc;
col reads    format 9,999,999,990 heading 'Reads'
col to2      format 999,999,999   heading '0 - 2 ms'
col to4      format 999,999,999   heading '2 - 4 ms'
col to8      format 999,999,999   heading '4 - 8 ms '
col to16     format 999,999,999   heading '8 - 16 ms'
col to32     format 999,999,999   heading '16 - 32 ms'
col over32   format 999,999,999   heading '32+ ms'

break on tsname skip 1;

select fse.tsname
     , fse.filename
     , sum(case when     (0 <= e.singleblkrdtim_milli) 
                     and (e.singleblkrdtim_milli <= 2)
                then (e.singleblkrds - nvl(b.singleblkrds,0)) else 0 end) to2
     , sum(case when     ( e.singleblkrdtim_milli = 4)
                then (e.singleblkrds - nvl(b.singleblkrds,0)) else 0 end) to4
     , sum(case when     ( e.singleblkrdtim_milli = 8)
                then (e.singleblkrds - nvl(b.singleblkrds,0)) else 0 end) to8
     , sum(case when     ( e.singleblkrdtim_milli = 16)
                then (e.singleblkrds - nvl(b.singleblkrds,0)) else 0 end) to16
     , sum(case when     ( e.singleblkrdtim_milli = 32)
                then (e.singleblkrds - nvl(b.singleblkrds,0)) else 0 end) to32
     , sum(case when   32 < e.singleblkrdtim_milli
                then (e.singleblkrds - nvl(b.singleblkrds,0)) else 0 end) over32
  from stats$file_histogram e
     , stats$file_histogram b
     , stats$filestatxs     fse
 where b.snap_id(+)         = :bid
   and e.snap_id            = :eid
   and e.dbid               = :dbid
   and b.dbid(+)            = e.dbid
   and e.instance_number    = :inst_num
   and b.instance_number(+) = e.instance_number
   and b.file#(+)           = e.file#
   and b.singleblkrdtim_milli(+) = e.singleblkrdtim_milli
   and fse.snap_id          = e.snap_id
   and fse.dbid             = e.dbid
   and fse.instance_number  = e.instance_number
   and fse.file#            = e.file#
   and (e.singleblkrds - nvl(b.singleblkrds,0)) > 0
   and '&&file_histogram' = 'Y'
 group by fse.tsname
        , fse.filename
union all
select tse.tsname
     , tse.filename
     , sum(case when     (0 <= e.singleblkrdtim_milli) 
                     and (e.singleblkrdtim_milli <= 2)
                then (e.singleblkrds - nvl(b.singleblkrds,0)) else 0 end) to2
     , sum(case when     ( e.singleblkrdtim_milli = 4)
                then (e.singleblkrds - nvl(b.singleblkrds,0)) else 0 end) to4
     , sum(case when     ( e.singleblkrdtim_milli = 8)
                then (e.singleblkrds - nvl(b.singleblkrds,0)) else 0 end) to8
     , sum(case when     ( e.singleblkrdtim_milli = 16)
                then (e.singleblkrds - nvl(b.singleblkrds,0)) else 0 end) to16
     , sum(case when     ( e.singleblkrdtim_milli = 32)
                then (e.singleblkrds - nvl(b.singleblkrds,0)) else 0 end) to32
     , sum(case when   32 < e.singleblkrdtim_milli
                then (e.singleblkrds - nvl(b.singleblkrds,0)) else 0 end) over32
  from stats$temp_histogram e
     , stats$temp_histogram b
     , stats$tempstatxs     tse
 where b.snap_id(+)         = :bid
   and e.snap_id            = :eid
   and e.dbid               = :dbid
   and b.dbid(+)            = e.dbid
   and e.instance_number    = :inst_num
   and b.instance_number(+) = e.instance_number
   and b.file#(+)           = e.file#
   and b.singleblkrdtim_milli(+) = e.singleblkrdtim_milli
   and tse.snap_id          = e.snap_id
   and tse.dbid             = e.dbid
   and tse.instance_number  = e.instance_number
   and tse.file#            = e.file#
   and (e.singleblkrds - nvl(b.singleblkrds,0)) > 0
   and '&&file_histogram' = 'Y'
 group by tse.tsname
        , tse.filename;



--
--  Buffer pools

ttitle lef 'Buffer Pool Statistics  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
       lef '-> Standard block size Pools  D: default,  K: keep,  R: recycle' -
       skip 1 -
       lef '-> Default Pools for other block sizes: 2k, 4k, 8k, 16k, 32k' -
       skip 1 -
       lef '-> Buffers: the number of buffers.  Units of K, M, G are divided by 1000' -
       skip 2;

col id      format 99            heading 'Set|Id';
col name    format a3            heading 'P' trunc;
col buffs   format 9,999,999,999 heading 'Buffer|Gets';
col conget  format 9,999,999,999 heading 'Consistent|Gets';
col phread  format 999,999,999   heading 'Physical|Reads';
col phwrite format 99,999,999    heading 'Physical|Writes';
col fbwait  format 99,999        heading 'Free|Buffer|Waits';
col wcwait  format 999           heading 'Writ|Comp|Wait';
col bbwait  format 9,999,999     heading 'Buffer|Busy|Waits'
col poolhr  format 999           heading 'Pool|Hit%'
col numbufs format a7            heading 'Buffers'
-- col numbufs format 9,999,999     heading 'Number of|Buffers'

select replace(e.block_size/1024||'k', :bs/1024||'k', substr(e.name,1,1)) name
    ,  lpad(case
              when e.set_msize <= 9999
                   then to_char(e.set_msize)||' '
              when trunc((e.set_msize)/1000) <= 9999
                   then to_char(trunc((e.set_msize)/1000))||'K'
              when trunc((e.set_msize)/1000000) <= 9999
                   then to_char(trunc((e.set_msize)/1000000))||'M'
              when trunc((e.set_msize)/1000000000) <= 9999
                   then to_char(trunc((e.set_msize)/1000000000))||'G'
              when trunc((e.set_msize)/1000000000000) <= 9999
                   then to_char(trunc((e.set_msize)/1000000000000))||'T'
              else substr(to_char(trunc((e.set_msize)/1000000000000000))||'P', 1, 5) end
            , 7, ' ') numbufs
     , decode(   e.db_block_gets     - nvl(b.db_block_gets,0)
              +  e.consistent_gets   - nvl(b.consistent_gets,0)
             , 0, to_number(null)
             , (100* (1 - (  (e.physical_reads - nvl(b.physical_reads,0))
                           / (  e.db_block_gets     - nvl(b.db_block_gets,0)
                              + e.consistent_gets   - nvl(b.consistent_gets,0))
                          )
                     )
               )
             )                                                poolhr
     ,    e.db_block_gets    - nvl(b.db_block_gets,0)
       +  e.consistent_gets  - nvl(b.consistent_gets,0)       buffs
     , e.physical_reads      - nvl(b.physical_reads,0)        phread
     , e.physical_writes     - nvl(b.physical_writes,0)       phwrite
     , e.free_buffer_wait    - nvl(b.free_buffer_wait,0)      fbwait
     , e.write_complete_wait - nvl(b.write_complete_wait,0)   wcwait
     , e.buffer_busy_wait    - nvl(b.buffer_busy_wait,0)      bbwait
  from stats$buffer_pool_statistics b
     , stats$buffer_pool_statistics e
 where b.snap_id(+)         = :bid
   and e.snap_id            = :eid
   and b.dbid(+)            = :dbid
   and e.dbid               = :dbid
   and b.dbid(+)            = e.dbid
   and b.instance_number(+) = :inst_num
   and e.instance_number    = :inst_num
   and b.instance_number(+) = e.instance_number
   and b.id(+)              = e.id
 order by e.name;


set newpage 1;
set heading off;
ttitle off;

select    'The following buffer pool no longer exists in the end snapshot: '
       || replace(b.block_size/1024||'k', :bs/1024||'k', substr(b.name,1,1))
  from stats$buffer_pool_statistics b
 where b.snap_id      = :bid
   and b.dbid         = :dbid
   and b.instance_number = :inst_num
minus
select    'The following buffer pool no longer exists in the end snapshot: '
       || replace(e.block_size/1024||'k', :bs/1024||'k', substr(e.name,1,1))
  from stats$buffer_pool_statistics e
 where e.snap_id      = :eid
   and e.dbid         = :dbid
   and e.instance_number = :inst_num;

set colsep ' ';
set underline on;
set heading on;



--
--  Instance Recovery Stats

ttitle lef 'Instance Recovery Stats  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
       '-> B: Begin snapshot,  E: End snapshot' -
       skip 2;

column tm    format       9999 heading 'Targt|MTTR|(s)' just c;
column em    format       9999 heading 'Estd|MTTR|(s)'   just c;
column beg   format a1         heading '';
column rei   format  999999999 heading 'Recovery|Estd IOs' just c;
column arb   format   99999999 heading 'Actual|Redo Blks' just c;
column trb   format   99999999 heading 'Target|Redo Blks' just c;
column lfrb  format  999999999 heading 'Log File|Size|Redo Blks' just c;
column lctrb format   99999999 heading 'Log Ckpt|Timeout|Redo Blks' just c;
column lcirb format 99999999999 heading 'Log Ckpt|Interval|Redo Blks' just c;
column fsirb format  999999999 heading 'Fast|Start IO|Redo Blks';
column cbr   format    9999999 heading 'Ckpt|Block|Writes';
column snid  noprint;

select 'B'                            beg
     , target_mttr                    tm
     , estimated_mttr                 em
     , recovery_estimated_ios         rei
     , actual_redo_blks               arb
     , target_redo_blks               trb
     , log_file_size_redo_blks        lfrb
     , log_chkpt_timeout_redo_blks    lctrb
     , log_chkpt_interval_redo_blks   lcirb
     , snap_id                        snid 
  from stats$instance_recovery b
 where b.snap_id         = :bid
   and b.dbid            = :dbid
   and b.instance_number = :inst_num
union all
select 'E'                            beg
     , target_mttr                    tm
     , estimated_mttr                 em
     , recovery_estimated_ios         rei
     , actual_redo_blks               arb
     , target_redo_blks               trb
     , log_file_size_redo_blks        lfrb
     , log_chkpt_timeout_redo_blks    lctrb
     , log_chkpt_interval_redo_blks   lcirb
     , snap_id                        snid
  from stats$instance_recovery e
 where e.snap_id         = :eid
   and e.dbid            = :dbid
   and e.instance_number = :inst_num
order by snid;



--
--  Buffer Pool Advisory

set newpage none;
set heading off;
set termout off;
ttitle off;
repfooter off;

column k2_cache  new_value  k2_cache noprint;
column k4_cache  new_value  k4_cache noprint;
column k8_cache  new_value  k8_cache noprint;
column k16_cache new_value k16_cache noprint;
column k32_cache new_value k32_cache noprint;
column def_cache new_value def_cache noprint;
column rec_cache new_value rec_cache noprint;
column kee_cache new_value kee_cache noprint;

select nvl(sum (case when name = 'db_2k_cache_size'
                 then value else '0' end),'0')          k2_cache
     , nvl(sum (case when name = 'db_4k_cache_size'
                 then value else '0' end),'0')          k4_cache
     , nvl(sum (case when name = 'db_8k_cache_size'
                 then value else '0' end),'0')          k8_cache
     , nvl(sum (case when name = 'db_16k_cache_size'
                 then value else '0' end),'0')          k16_cache
     , nvl(sum (case when name = 'db_32k_cache_size'
                 then value else '0' end),'0')          k32_cache
     , decode(nvl(sum (case when name = 'db_keep_cache_size'
                       then value else '0' end),'0')
             , '0'
             , nvl(sum (case when name = 'buffer_pool_keep'
                        then to_char(decode( 0
                        , instrb(value, 'buffers')
                        , value
                        , decode(1, instrb(value, 'lru_latches')
                        , substr(value, instrb(value,',')+10, 9999)
                        , decode(0,instrb(value, ', lru')
                        , substrb(value,9,99999) 
                        , substrb(substrb(value,1,instrb(value,', lru_latches:')-1),9,99999) ))) * :bs) else '0' end),'0')
             , sum (case when name = 'db_keep_cache_size'
                      then value else '0' end))         kee_cache
     , decode(nvl(sum (case when name = 'db_recycle_cache_size'
                       then value else '0' end),'0')
             , '0'
             , nvl(sum (case when name = 'buffer_pool_recycle'
                        then to_char(decode( 0
                        , instrb(value, 'buffers')
                        , value
                        , decode(1, instrb(value, 'lru_latches')
                        , substr(value, instrb(value,',')+10, 9999)
                        , decode(0,instrb(value, ', lru')
                        , substrb(value,9,99999) 
                        , substrb(substrb(value,1,instrb(value,', lru_latches:')-1),9,99999) ))) * :bs) else '0' end),'0')
             , sum (case when name = 'db_recycle_cache_size'
                       then value else '0' end) )       rec_cache
     , decode(nvl(sum (case when name = '__db_cache_size'
                       then value else '0' end) , '0')
             , '0'
             , nvl(sum (case when name = 'db_block_buffers'
                        then to_char(value * :bs) else '0' end),'0')
             , sum (case when name = '__db_cache_size'
                       then value else '0' end) )       def_cache
 from stats$parameter
where name in ( 'db_2k_cache_size'     ,'db_4k_cache_size'
               ,'db_8k_cache_size'     ,'db_16k_cache_size'
               ,'db_32k_cache_size'
               ,'__db_cache_size'        ,'db_block_buffers'
               ,'db_keep_cache_size'   ,'buffer_pool_keep'
               ,'db_recycle_cache_size','buffer_pool_recycle')
  and snap_id         = :eid
  and dbid            = :dbid
  and instance_number = :inst_num;

variable k2_cache  number;
variable k4_cache  number
variable k8_cache  number;
variable k16_cache number;
variable k32_cache number;
variable def_cache number;
variable rec_cache number;
variable kee_cache number;
begin
  :k2_cache  := &k2_cache/1024;
  :k4_cache  := &k4_cache/1024;
  :k8_cache  := &k8_cache/1024;
  :k16_cache := &k16_cache/1024;
  :k32_cache := &k32_cache/1024;
  :def_cache := &def_cache/1024;
  :rec_cache := &rec_cache/1024;
  :kee_cache := &kee_cache/1024;
end;
/


set termout on;
set heading on;
repfooter center -
   '-------------------------------------------------------------';

ttitle lef 'Buffer Pool Advisory  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'End Snap: ' format 99999999 end_snap -
       skip 1 -
       lef '-> Only rows with estimated physical reads >0 are displayed' -
       skip 1 -
       lef '-> ordered by Pool, Block Size, Buffers For Estimate' -
       skip 2;

column id            format 999;
column bpool         format a3                   heading 'P' trunc;
column order_def_bs  noprint
column advice_status format a2 trunc             heading 'ON';
column block_size    format 99999    heading 'Block|Size';
column sfe           format 999,999    heading 'Size for|Est (M)';
column bfe           format 999,999,999    heading 'Buffers|(thousands)';
column eprf          format         990.9       heading 'Est|Phys|Read|Factr';
column epr           format 9,999,999,999    heading 'Estimated|Phys Reads|(thousands)';
column bcsf          format 99.9                 heading 'Size|Factr'
column eprt          format 999,999,999          heading 'Est Phys|Read Time'
column epdbt         format 999.9                heading 'Est|% dbtime|for Rds'

select replace( block_size/1024||'k', :bs/1024||'k'
              , substr(name,1,1))    bpool
     , decode(block_size, :bs, 1, 2) order_def_bs
     , size_for_estimate             sfe
     , nvl(  size_factor
           , decode(    replace(block_size/1024||'k', :bs/1024||'k'
                      , substr(name,1,1))
                    , '2k' , size_for_estimate*1024/:k2_cache
                    , '4k' , size_for_estimate*1024/:k4_cache
                    , '8k' , size_for_estimate*1024/:k8_cache
                    , '16k', size_for_estimate*1024/:k16_cache
                    , '32k', size_for_estimate*1024/:k32_cache
                    , 'D'  , size_for_estimate*1024/:def_cache
                    , 'K'  , size_for_estimate*1024/:kee_cache
                    , 'R'  , size_for_estimate*1024/:rec_cache
                    )
          ) bcsf
     , buffers_for_estimate/1000     bfe
     , estd_physical_read_factor     eprf
     , estd_physical_reads/1000      epr
     , estd_physical_read_time       eprt
     , estd_pct_of_db_time_for_reads epdbt
  from stats$db_cache_advice
 where snap_id             = :eid
   and dbid                = :dbid
   and instance_number     = :inst_num
   and estd_physical_reads > 0
 order by order_def_bs, block_size, name, buffers_for_estimate;

set newpage 1;


--
--  Buffer waits

ttitle lef 'Buffer wait Statistics  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
       lef '-> ordered by wait time desc, waits desc' -
       skip 2;

column class                            heading 'Class';
column icnt     format 99,999,990       heading 'Waits';
column itim     format  9,999,990       heading 'Total Wait Time (s)';
column iavg     format    999,990       heading 'Avg Time (ms)' just c;

select e.class
     , e.wait_count  - nvl(b.wait_count,0)       icnt
     , (e.time        - nvl(b.time,0))/100       itim
     ,10*  (e.time       - nvl(b.time,0))
         / (e.wait_count - nvl(b.wait_count,0))  iavg  
  from stats$waitstat b
     , stats$waitstat e
 where b.snap_id         = :bid
   and e.snap_id         = :eid
   and b.dbid            = :dbid
   and e.dbid            = :dbid
   and b.dbid            = e.dbid
   and b.instance_number = :inst_num
   and e.instance_number = :inst_num
   and b.instance_number = e.instance_number
   and b.class           = e.class
   and b.wait_count      < e.wait_count
 order by itim desc, icnt desc;

set newpage 0;



--
--  PGA Memory Statistics

ttitle lef 'PGA Aggr Target Stats  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
       lef '-> B: Begin snap   E: End snap (rows identified with B or E contain data' -
       skip 1 -
       lef '   which is absolute i.e. not diffed over the interval)' -
       skip 1 - 
       lef '-> PGA cache hit % - percentage of W/A (WorkArea) data processed only in-memory' - 
       skip 1 -
       lef '-> Auto PGA Target - actual workarea memory target'-
       skip 1 -
       lef '-> W/A PGA Used    - amount of memory used for all Workareas (manual + auto)'-
       skip 1 -
       lef '-> %PGA W/A Mem    - percentage of PGA memory allocated to workareas'-
       skip 1 -
       lef '-> %Auto W/A Mem   - percentage of workarea memory controlled by Auto Mem Mgmt'-
       skip 1 -
       lef '-> %Man W/A Mem    - percentage of workarea memory under manual control'-
       skip 2;

repfooter off;

--  Show the PGA cache hit percentage for this interval

col tbp            format 9,999,999,999   heading 'W/A MB Processed'
col tbrw           format 9,999,999,999   heading 'Extra W/A MB Read/Written'
col calc_cache_pct format           990.0 heading 'PGA Cache Hit %'

select 100
       * (e.bytes   - nvl(b.bytes,0))
       / (e.bytes   - nvl(b.bytes,0)  + e.bytesrw - nvl(b.bytesrw,0))  calc_cache_pct
     , (e.bytes     - nvl(b.bytes,0))  /1024/1024               tbp
     , (e.bytesrw   - nvl(b.bytesrw,0))/1024/1024               tbrw
  from (select sum(case when name = 'bytes processed'
                        then value else 0 end)                  bytes
             , sum(case when name = 'extra bytes read/written'
                        then value else 0 end)                  bytesrw
         from stats$pgastat e1
        where e1.snap_id          = :eid
          and e1.dbid             = :dbid
          and e1.instance_number  = :inst_num
          and e1.name             in ('bytes processed','extra bytes read/written')
       ) e
     , (select sum(case when name = 'bytes processed'
                        then value else 0 end)                  bytes
             , sum(case when name = 'extra bytes read/written'
                        then value else 0 end)                  bytesrw
         from stats$pgastat b1
        where b1.snap_id          = :bid
          and b1.dbid             = :dbid
          and b1.instance_number  = :inst_num
          and b1.name             in ('bytes processed','extra bytes read/written')
       ) b
  where e.bytes - nvl(b.bytes,0) > 0;

set newpage 1;


-- Display overflow warning, if needed

ttitle off;
set heading off;
col nl format a78 newline

select 'Warning:  pga_aggregate_target was set too low for current workload, as this' nl
     , '          value was exceeded during this interval.  Use the PGA Advisory view'    nl
     , '          to help identify a different value for pga_aggregate_target.'                nl
  from stats$pgastat   e
     , stats$pgastat   b
     , stats$parameter p
 where e.snap_id             = :eid
   and e.dbid                = :dbid
   and e.instance_number     = :inst_num
   and e.name                = 'over allocation count'
   and b.snap_id(+)          = :bid
   and b.dbid(+)             = e.dbid
   and b.instance_number(+)  = e.instance_number
   and b.name(+)             = e.name
   and e.value > nvl(b.value,0)
   and p.snap_id             = :eid
   and p.dbid                = :dbid
   and p.instance_number     = :inst_num
   and p.name                = 'workarea_size_policy'
   and p.value               = 'AUTO';


set heading on;
repfooter center -
   '-------------------------------------------------------------';

-- Display Begin and End statistics for this interval

column snap         format    a1        heading '';
column pgaat        format    999,999   heading 'PGA Aggr|Target(M)'  just c;
column pat          format    999,999   heading 'Auto PGA|Target(M)'  just c;
column tot_pga_allo format    999,990.9 heading 'PGA Mem|Alloc(M)'    just c;
column tot_tun_used format    999,990.9 heading 'W/A PGA|Used(M)'     just c;
column pct_tun      format        999.9 heading '%PGA|W/A|Mem'        just c;
column pct_auto_tun format        999.9 heading '%Auto|W/A|Mem'       just c;
column pct_man_tun  format        999.9 heading '%Man|W/A|Mem'        just c;
column glo_mem_bnd  format  9,999,999   heading 'Global Mem|Bound(K)' just c;

select 'B'                                                   snap
     , to_number(p.value)/1024/1024                          pgaat
     , mu.pat/1024/1024                                      pat
     , mu.PGA_alloc/1024/1024                                tot_pga_allo
     , (mu.PGA_used_auto + mu.PGA_used_man)/1024/1024        tot_tun_used
     , 100*(mu.PGA_used_auto + mu.PGA_used_man) / PGA_alloc  pct_tun
     , decode(mu.PGA_used_auto + mu.PGA_used_man, 0, 0
             , 100* mu.PGA_used_auto/(mu.PGA_used_auto + mu.PGA_used_man)
             )                                               pct_auto_tun
     , decode(mu.PGA_used_auto + mu.PGA_used_man, 0, 0
             , 100* mu.PGA_used_man  / (mu.PGA_used_auto + mu.PGA_used_man)
             )                                               pct_man_tun
     , mu.glob_mem_bnd/1024                                  glo_mem_bnd
  from (select sum(case when name = 'total PGA allocated'
                        then value else 0 end)               PGA_alloc
             , sum(case when name = 'total PGA used for auto workareas'
                        then value else 0 end)               PGA_used_auto
             , sum(case when name = 'total PGA used for manual workareas'
                        then value else 0 end)               PGA_used_man
             , sum(case when name = 'global memory bound'
                        then value else 0 end)               glob_mem_bnd
             , sum(case when name = 'aggregate PGA auto target'
                        then value else 0 end)               pat
          from stats$pgastat pga
         where pga.snap_id            = :bid
           and pga.dbid               = :dbid
           and pga.instance_number    = :inst_num
       ) mu
     , stats$parameter p
where p.snap_id            = :bid
  and p.dbid               = :dbid
  and p.instance_number    = :inst_num
  and p.name               = 'pga_aggregate_target'
  and p.value             != '0'
union all
select 'E'                                                   snap
     , to_number(p.value)/1024/1024                          pgaat
     , mu.pat/1024/1024                                      pat
     , mu.PGA_alloc/1024/1024                                tot_pga_allo
     , (mu.PGA_used_auto + mu.PGA_used_man)/1024/1024        tot_tun_used
     , 100*(mu.PGA_used_auto + mu.PGA_used_man) / PGA_alloc  pct_tun
     , decode(mu.PGA_used_auto + mu.PGA_used_man, 0, 0
             , 100* mu.PGA_used_auto/(mu.PGA_used_auto + mu.PGA_used_man)
             )                                               pct_auto_tun
     , decode(mu.PGA_used_auto + mu.PGA_used_man, 0, 0
             , 100* mu.PGA_used_man  / (mu.PGA_used_auto + mu.PGA_used_man)
             )                                               pct_man_tun
     , mu.glob_mem_bnd/1024                                  glo_mem_bnd
  from (select sum(case when name = 'total PGA allocated'
                        then value else 0 end)               PGA_alloc
             , sum(case when name = 'total PGA used for auto workareas'
                        then value else 0 end)               PGA_used_auto
             , sum(case when name = 'total PGA used for manual workareas'
                        then value else 0 end)               PGA_used_man
             , sum(case when name = 'global memory bound'
                        then value else 0 end)               glob_mem_bnd
             , sum(case when name = 'aggregate PGA auto target'
                        then value else 0 end)               pat
          from stats$pgastat pga
         where pga.snap_id            = :eid
           and pga.dbid               = :dbid
           and pga.instance_number    = :inst_num
       ) mu
     , stats$parameter p
 where p.snap_id            = :eid
   and p.dbid               = :dbid
   and p.instance_number    = :inst_num
   and p.name               = 'pga_aggregate_target'
   and p.value             != '0'
 order by snap;

set heading on;
set newpage 1;



--  PGA usage Histogram

ttitle lef 'PGA Aggr Target Histogram  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
       lef '-> Optimal Executions are purely in-memory operations' -
       skip 2;

col low_o    format a7             heading 'Low|Optimal'  just r
col high_o   format a7             heading 'High|Optimal' just r
col tot_e    format  9,999,999,999 heading 'Total Execs'
col opt_e    format    999,999,999 heading 'Optimal Execs'
col one_e    format    999,999,999 heading '1-Pass Execs'
col mul_e    format    999,999,999 heading 'M-Pass Execs'

select case when e.low_optimal_size >= 1024*1024*1024*1024
            then lpad(round(e.low_optimal_size/1024/1024/1024/1024) || 'T',7)
            when e.low_optimal_size >= 1024*1024*1024
            then lpad(round(e.low_optimal_size/1024/1024/1024) || 'G' ,7)
            when e.low_optimal_size >= 1024*1024
            then lpad(round(e.low_optimal_size/1024/1024) || 'M',7)
            when e.low_optimal_size >= 1024
            then lpad(round(e.low_optimal_size/1024) || 'K',7)
            else lpad(e.low_optimal_size || 'B',7)
       end                                              low_o
     , case when e.high_optimal_size >= 1024*1024*1024*1024
            then lpad(round(e.high_optimal_size/1024/1024/1024/1024) || 'T',7) 
            when e.high_optimal_size >= 1024*1024*1024
            then lpad(round(e.high_optimal_size/1024/1024/1024) || 'G',7) 
            when e.high_optimal_size >= 1024*1024
            then lpad(round(e.high_optimal_size/1024/1024) || 'M',7) 
            when e.high_optimal_size >= 1024
            then lpad(round(e.high_optimal_size/1024) || 'K',7)
            else e.high_optimal_size || 'B'
       end                                              high_o
     , e.total_executions       - nvl(b.total_executions,0)        tot_e
     , e.optimal_executions     - nvl(b.optimal_executions,0)      opt_e
     , e.onepass_executions     - nvl(b.onepass_executions,0)      one_e
     , e.multipasses_executions - nvl(b.multipasses_executions,0)  mul_e
  from stats$sql_workarea_histogram e
     , stats$sql_workarea_histogram b
 where e.snap_id              = :eid
   and e.dbid                 = :dbid
   and e.instance_number      = :inst_num
   and b.snap_id(+)           = :bid
   and b.dbid(+)              = e.dbid
   and b.instance_number(+)   = e.instance_number
   and b.low_optimal_size(+)  = e.low_optimal_size
   and b.high_optimal_size(+) = e.high_optimal_size
   and e.total_executions  - nvl(b.total_executions,0) > 0
 order by e.low_optimal_size;
 

--  PGA Advisory

ttitle lef 'PGA Memory Advisory  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'End Snap: ' format 99999999 end_snap -
       skip 1 -
       lef '-> When using Auto Memory Mgmt, minimally choose a pga_aggregate_target value'-
       skip 1 - 
       lef '   where Estd PGA Overalloc Count is 0' -
       skip 2;

col pga_t  format     9,999,999     heading 'PGA Target|Est (MB)'
col pga_tf format          9990.0   heading 'Size|Factr'
col byt_p  format 9,999,999,990.0   heading 'W/A MB|Processed'
col byt_rw format 9,999,999,990.0   heading 'Estd Extra|W/A MB Read/|Written to Disk' just c
col epchp  format           990.0   heading 'Estd PGA|Cache|Hit %'
col eoc    format     9,999,999     heading 'Estd PGA|Overalloc|Count'

select pga_target_for_estimate/1024/1024  pga_t
     , pga_target_factor                  pga_tf
     , bytes_processed/1024/1024          byt_p
     , estd_extra_bytes_rw/1024/1024      byt_rw
     , estd_pga_cache_hit_percentage      epchp
     , estd_overalloc_count               eoc
  from stats$pga_target_advice e
 where snap_id             = :eid
   and dbid                = :dbid
   and instance_number     = :inst_num
 order by pga_target_for_estimate;


--
--  PGA Memory Stats

set newpage 0;

ttitle lef 'Process Memory Summary Stats  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
       lef '-> B: Begin snap   E: End snap' -
       skip 1 -
       lef '-> All rows below contain absolute values (i.e. not diffed over the interval)' -
       skip 1 -
       lef '-> Max Alloc is Maximum PGA Allocation size at snapshot time' -
       skip 1 -
       lef '   Hist Max Alloc is the Historical Max Allocation for still-connected processes' -
       skip 1 -
       lef '-> Num Procs or Allocs:  For Begin/End snapshot lines, it is the number of' -
       skip 1 -
       lef '   processes. For Category lines, it is the number of allocations' -
       skip 1 -
       lef '-> ordered by Begin/End snapshot, Alloc (MB) desc' -
       skip 2;

col b_or_e                             heading ''
col ord_col noprint
col snid    noprint
col cat              format    a8      heading 'Category' trunc
col tot_alloc_mb     format 99,999.9   heading 'Alloc|(MB)' just c
col tot_used_mb      format 99,999.9   heading 'Used|(MB)' just c
col tot_free_pga_mb  format  9,999.9   heading 'Freeabl|(MB)' just c
col avg_alloc_mb     format  9,999.9   heading 'Avg|Alloc|(MB)' just c
col cov_alloc_mb     format    999.9   heading 'Coeff of|Variance' just c
col stddev_alloc_mb  format    999.9   heading 'Std Dev|Alloc|(MB)' just c
col max_alloc_mb     format 99,999     heading 'Max|Alloc|(MB)' just c
col max_max_alloc_mb format  9,999     heading 'Hist|Max|Alloc|(MB)' just c
col nza              format  9,999     heading 'Num|Procs|or|Allocs' just c
break on b_or_e

select *
  from (select decode(snap_id, :bid, 'B', :eid, 'E')  b_or_e
             , 1                                      ord_col
             , snap_id                                snid
             , '---------'                            cat
             , pga_alloc_mem/&&btomb                  tot_alloc_mb
             , pga_used_mem/&&btomb                   tot_used_mb
             , pga_freeable_mem/&&btomb               tot_free_pga_mb
             , avg_pga_alloc_mem/&&btomb              avg_alloc_mb
             , stddev_pga_alloc_mem/&&btomb           stddev_alloc_mb
             , max_pga_alloc_mem/&&btomb              max_alloc_mb
             , max_pga_max_mem/&&btomb                max_max_alloc_mb
             , num_processes                          nza
          from stats$process_rollup
         where snap_id           in (:bid, :eid)
           and dbid               = :dbid
           and instance_number    = :inst_num
           and pid                = -9
        union all
        select decode(snap_id, :bid, 'B', :eid, 'E')  b_or_e
             , 2                                      ord_col
             , snap_id                                snid
             , category                               cat
             , allocated/&&btomb                      tot_alloc_mb
             , used/&&btomb                           tot_used_mb
             , to_number(null)                        tot_free_pga_mb
             , avg_allocated /&&btomb                 avg_alloc_mb
             , stddev_allocated/&&btomb               stddev_alloc_mb
             , max_allocated/&&btomb                  max_alloc_mb
             , max_max_allocated/&&btomb              max_max_alloc_mb
             , non_zero_allocations                   nza
          from stats$process_memory_rollup
         where snap_id            in (:bid, :eid)
           and dbid                = :dbid
           and instance_number     = :inst_num
           and pid                 = -9
       )
 order by snid, ord_col, tot_alloc_mb desc;


--
--  PGA Allocation by Component summary

clear breaks
set newpage 1;

ttitle lef 'Top Process Memory (by component)  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
       lef '-> ordered by Begin/End snapshot, Alloc (MB) desc' -
       skip 2;

col b_or_e                              heading ''
col snid             noprint
col ord_col          noprint
col pid              format    99999    heading 'PId'
col cat              format    a13      heading 'Category' trunc
col tot_alloc_mb     format    9999.9   heading 'Alloc|(MB)' just c
col tot_used_mb      format    9999.9   heading 'Used|(MB)' just c
col max_alloc_mb     format    9999.9   heading 'Max|Alloc (MB)' just c
col max_max_alloc_mb format    9999.9   heading 'Hist Max|Alloc (MB)' just c
col tot_alloc_mb2    noprint

clear breaks

break on b_or_e on pid

select * 
  from (select decode(snap_id, :bid, 'B', :eid, 'E') b_or_e
             , snap_id                      snid
             , 1                            ord_col
             , pid                          pid
             , rpad(substr( program, instrb(program,'(') +1 
                          , instrb(program, ')')-1-instrb(program,'(')) || ' '
                   , 13, '-')               cat
             , pga_alloc_mem/&&btomb        tot_alloc_mb
             , pga_used_mem/&&btomb         tot_used_mb
             , pga_freeable_mem/&&btomb     tot_free_pga_mb
             , max_pga_alloc_mem/&&btomb    max_alloc_mb
             , max_pga_max_mem/&&btomb      max_max_alloc_mb
             , pga_alloc_mem/&&btomb        tot_alloc_mb2
          from stats$process_rollup
         where snap_id             in (:bid, :eid)
           and dbid                = :dbid
           and instance_number     = :inst_num
           and pid                != -9
       union all
       select decode(pmr.snap_id, :bid, 'B', :eid, 'E') b_or_e
            , pmr.snap_id                    snid
            , 2                              ord_col
            , pmr.pid                        pid
            , pmr.category                   cat
            , pmr.allocated/&&btomb          tot_alloc_mb
            , pmr.used/&&btomb               tot_used_mb
            , to_number(null)                pga_free_mb
            , pmr.max_allocated/&&btomb      max_alloc_mb
            , pmr.max_max_allocated/&&btomb  max_max_alloc_mb
            , pr.pga_alloc_mem/&&btomb       tot_alloc_mb2
         from stats$process_memory_rollup pmr
            , stats$process_rollup        pr
        where pmr.snap_id             in (:bid, :eid)
          and pmr.dbid                = :dbid
          and pmr.instance_number     = :inst_num
          and pmr.pid                != -9
          and pr.snap_id = pmr.snap_id
          and pr.dbid    = pmr.dbid
          and pr.instance_number = pmr.instance_number
          and pr.pid             = pmr.pid
          and pmr.serial#        = pmr.serial#
       )
 order by snid, tot_alloc_mb2 desc, pid, ord_col,tot_alloc_mb desc;

set newpage 0


--
--  Enqueue activity

ttitle lef 'Enqueue activity  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
       lef '-> only enqueues with waits are shown' -
       skip 1 -
       lef '-> Enqueue stats gathered prior to 10g should not be compared with 10g data' -
       skip 1 -
       lef '-> ordered by Wait Time desc, Waits desc' -
       skip 2;

col ety   format         a78    heading 'Enqueue Type (Request Reason)' trunc;
col reqs  format 999,999,990    heading 'Requests' newline;
col sreq  format 999,999,990    heading 'Succ Gets';
col freq  format  99,999,990    heading 'Failed Gets';
col waits format  99,999,990    heading 'Waits';
col wttm  format 999,999,999    heading 'Wt Time (s)'    just c;
col awttm format   9,999,999.99 heading 'Av Wt Time(ms)' just c;

select /*+ ordered */
         e.eq_type || '-' || to_char(nvl(l.name,' '))
      || decode( upper(e.req_reason)
               , 'CONTENTION', null
               , '-',          null
               , ' ('||e.req_reason||')')                ety
     , e.total_req#    - nvl(b.total_req#,0)            reqs
     , e.succ_req#     - nvl(b.succ_req#,0)             sreq
     , e.failed_req#   - nvl(b.failed_req#,0)           freq
     , e.total_wait#   - nvl(b.total_wait#,0)           waits
     , (e.cum_wait_time - nvl(b.cum_wait_time,0))/1000  wttm
     , decode(  (e.total_wait#   - nvl(b.total_wait#,0))
               , 0, to_number(NULL)
               , (  (e.cum_wait_time - nvl(b.cum_wait_time,0))
                  / (e.total_wait#   - nvl(b.total_wait#,0))
                 )
             )                                          awttm
  from stats$enqueue_statistics e
     , stats$enqueue_statistics b
     , v$lock_type              l
 where b.snap_id(+)         = :bid
   and e.snap_id            = :eid
   and b.dbid(+)            = :dbid
   and e.dbid               = :dbid
   and b.dbid(+)            = e.dbid
   and b.instance_number(+) = :inst_num
   and e.instance_number    = :inst_num
   and b.instance_number(+) = e.instance_number
   and b.eq_type(+)         = e.eq_type
   and b.req_reason(+)      = e.req_reason
   and e.total_wait# - nvl(b.total_wait#,0) > 0
   and l.type(+)            = e.eq_type
 order by wttm desc, waits desc;



--
--  Rollback segment

ttitle off;
repfooter off;
set newpage none;
set heading off;
set termout off;
column auto_undo new_value auto_undo noprint
select value auto_undo
  from stats$parameter
 where snap_id          = :eid
   and dbid             = :dbid
   and instance_number  = :inst_num
   and name             = 'undo_management';

repfooter center -
   '-------------------------------------------------------------';
set newpage 0;
set heading on;
set termout on;

ttitle lef 'Rollback Segment Stats  '-
           'DB/Inst: ' db_name '/' inst_name '  ' -
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
       lef '->A high value for "Pct Waits" suggests more rollback segments may be required' -
       skip 1 -
       lef '->RBS stats may not be accurate between begin and end snaps when using Auto Undo,' -
      skip 1 -
       lef '  managment, as RBS may be dynamically created and dropped as needed' -
       skip 2;

column usn      format 99990          heading 'RBS No' Just Cen;
column gets     format 999,999,990.9  heading 'Trans Table|Gets' Just Cen;
column waits    format 990.99         heading 'Pct|Waits';
column writes   format 99,999,999,990 heading 'Undo Bytes|Written' Just Cen;
column wraps    format 999,990        heading 'Wraps';
column shrinks  format 999,990        heading 'Shrinks';
column extends  format 999,990        heading 'Extends';
column rssize   format 99,999,999,990 heading 'Segment Size';
column active   format 99,999,999,990 heading 'Avg Active';
column optsize  format 99,999,999,990 heading 'Optimal Size';
column hwmsize  format 99,999,999,990 heading 'Maximum Size';

select b.usn
     , e.gets    - b.gets     gets
     , to_number(decode(e.gets ,b.gets, null,
       (e.waits  - b.waits) * 100/(e.gets - b.gets))) waits
     , e.writes  - b.writes   writes
     , e.wraps   - b.wraps    wraps
     , e.shrinks - b.shrinks  shrinks
     , e.extends - b.extends  extends
  from stats$rollstat b
     , stats$rollstat e
 where b.snap_id         = :bid
   and e.snap_id         = :eid
   and b.dbid            = :dbid
   and e.dbid            = :dbid
   and b.dbid            = e.dbid
   and b.instance_number = :inst_num
   and e.instance_number = :inst_num
   and b.instance_number = e.instance_number
   and e.usn             = b.usn
   and (   '&&auto_undo'               = 'MANUAL'
        or upper('&&display_rollstat') = 'Y'
       )
 order by e.usn;


ttitle lef 'Rollback Segment Storage  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
       lef '->Optimal Size should be larger than Avg Active'-
       skip 2;

select b.usn                                                       
     , e.rssize
     , e.aveactive active
     , to_number(decode(e.optsize, -4096, null,e.optsize)) optsize
     , e.hwmsize
  from stats$rollstat b
     , stats$rollstat e
 where b.snap_id         = :bid
   and e.snap_id         = :eid
   and b.dbid            = :dbid
   and e.dbid            = :dbid
   and b.dbid            = e.dbid
   and b.instance_number = :inst_num
   and e.instance_number = :inst_num
   and b.instance_number = e.instance_number
   and e.usn             = b.usn
   and (   '&&auto_undo'               = 'MANUAL'
        or upper('&&display_rollstat') = 'Y'
       )
 order by e.usn;


--
--  Undo Segment

ttitle lef 'Undo Segment Summary  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
       lef '-> Min/Max TR (mins) - Min and Max Tuned Retention (minutes)' -
       skip 1 -
       lef '-> STO - Snapshot Too Old count,  OOS - Out Of Space count' -
       skip 1 -
       lef '-> Undo segment block stats:' -
       skip 1 -
       lef '   uS - unexpired Stolen,   uR - unexpired Released,   uU - unexpired reUsed' -
       skip 1 -
       lef '   eS - expired   Stolen,   eR - expired   Released,   eU - expired   reUsed' -
       skip 2;
 
column undotsn  format           999 heading 'Undo|TS#';
column undob    format       99,999.0 heading 'Num Undo|Blocks (K)';
column txcnt    format 99,999,999,999 heading 'Number of|Transactions';
column maxq     format       999,999 heading 'Max Qry|Len (s)';
column maxc     format     9,999,999 heading 'Max Tx|Concy';
column mintun   format            a9 heading 'Min/Max|TR (mins)' wrap;
column snolno   format            a5 heading 'STO/|OOS' wrap;
column blkst    format a11           heading 'uS/uR/uU/|eS/eR/eU' wrap;
column unst     format         9,999 heading 'Unexp|Stolen' newline;
column unrl     format         9,999 heading 'Unexp|Relesd';
column unru     format         9,999 heading 'Unexp|Reused';
column exst     format         9,999 heading 'Exp|Stolen';
column exrl     format         9,999 heading 'Exp|Releas';
column exru     format         9,999 heading 'Exp|Reused';

select undotsn
     , sum(undoblks)/1000           undob
     , sum(txncount)                txcnt
     , max(maxquerylen)             maxq
     , max(maxconcurrency)          maxc
     ,         round(min(tuned_undoretention)/60,1)
       ||'/'|| round(max(tuned_undoretention)/60,1)   mintun
     ,         sum(ssolderrcnt)
       ||'/'|| sum(nospaceerrcnt)            snolno
     ,         sum(unxpstealcnt)
       ||'/'|| sum(unxpblkrelcnt)
       ||'/'|| sum(unxpblkreucnt)
       ||'/'|| sum(expstealcnt)
       ||'/'|| sum(expblkrelcnt)
       ||'/'|| sum(expblkreucnt)    blkst
  from stats$undostat
 where dbid            = :dbid
   and instance_number = :inst_num
   and end_time        >  to_date(:btime, 'YYYYMMDD HH24:MI:SS')
   and begin_time      <  to_date(:etime, 'YYYYMMDD HH24:MI:SS')
   and upper('&&display_undostat') = 'Y'
 group by undotsn;

set newpage 2;

ttitle lef 'Undo Segment Stats  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
       lef '-> Most recent ' &&top_n_undostat ' Undostat rows, ordered by End Time desc' -
       skip 2;

column undotsn  format         999 heading 'Undo|TS#' noprint;
column endt     format a12         heading 'End Time';
column undob    format  99,999,999 heading 'Num Undo|Blocks';
column txcnt    format 999,999,999 heading 'Number of|Transactions';
column maxq     format      99,999 heading 'Max Qry|Len (s)';
column maxc     format      99,999 heading 'Max Tx|Concy';
column mintun   format      99,999 heading 'Tun Ret|(mins)';
column snolno   format          a5 heading 'STO/|OOS' wrap;
column blkst    format a11         heading 'uS/uR/uU/|eS/eR/eU' wrap;

select undotsn
     , endt
     , undob
     , txcnt
     , maxq
     , maxc
     , mintun
     , snolno
     , blkst
  from (select undotsn
             , to_char(end_time,   'DD-Mon HH24:MI')    endt
             , undoblks                                 undob
             , txncount                                 txcnt
             , maxquerylen                              maxq
             , maxconcurrency                           maxc
             , tuned_undoretention/60                   mintun
             , ssolderrcnt || '/' || nospaceerrcnt      snolno
             ,         unxpstealcnt
               ||'/'|| unxpblkrelcnt
               ||'/'|| unxpblkreucnt
               ||'/'|| expstealcnt
               ||'/'|| expblkrelcnt
               ||'/'|| expblkreucnt                     blkst
          from stats$undostat
         where dbid            = :dbid
           and instance_number = :inst_num
           and end_time        >  to_date(:btime, 'YYYYMMDD HH24:MI:SS')
           and begin_time      <  to_date(:etime, 'YYYYMMDD HH24:MI:SS')
           and upper('&&display_undostat') = 'Y'
         order by begin_time desc
       )
 where rownum < &&top_n_undostat;

set newpage 0;



--
--  Latch Activity

ttitle lef 'Latch Activity  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
       lef '->"Get Requests", "Pct Get Miss" and "Avg Slps/Miss" are ' -
           'statistics for ' skip 1 -
           '  willing-to-wait latch get requests' -
       skip 1 -
       lef '->"NoWait Requests", "Pct NoWait Miss" are for ' -
           'no-wait latch get requests' -
       skip 1 -
       lef '->"Pct Misses" for both should be very close to 0.0' -
       skip 2;

column name     format a24              heading 'Latch' trunc;
column gets     format 9,999,999,990    heading 'Get|Requests';
column missed   format 990.9            heading 'Pct|Get|Miss';
column sleeps   format 990.9            heading 'Avg|Slps|/Miss';
column nowai    format 999,999,990      heading 'NoWait|Requests';
column imiss    format 990.9            heading 'Pct|NoWait|Miss';
column wt       format 99990            heading 'Wait|Time|(s)';

select b.name                                            name
     , e.gets    - b.gets                                gets
     , to_number(decode(e.gets, b.gets, null,
       (e.misses - b.misses) * 100/(e.gets - b.gets)))   missed
     , to_number(decode(e.misses, b.misses, null,
       (e.sleeps - b.sleeps)/(e.misses - b.misses)))     sleeps
     , (e.wait_time - b.wait_time)/1000000               wt
     , e.immediate_gets - b.immediate_gets               nowai
     , to_number(decode(e.immediate_gets,
                        b.immediate_gets, null,
                        (e.immediate_misses - b.immediate_misses) * 100 /
                        (e.immediate_gets   - b.immediate_gets)))     imiss
 from  stats$latch b
     , stats$latch e
 where b.snap_id         = :bid
   and e.snap_id         = :eid
   and b.dbid            = :dbid
   and e.dbid            = :dbid
   and b.dbid            = e.dbid
   and b.instance_number = :inst_num
   and e.instance_number = :inst_num
   and b.instance_number = e.instance_number
   and b.name            = e.name
   and (   e.gets           - b.gets
         + e.immediate_gets - b.immediate_gets
       ) > 0
 order by b.name;



--
--  Latch Sleep breakdown

ttitle lef 'Latch Sleep breakdown  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
       lef '-> ordered by misses desc' -
       skip 2;

column gets clear;
column name      format a26             heading 'Latch Name' trunc;
column gets      format 99,999,999,990  heading 'Get|Requests';
column sleeps    format 99,999,990      heading 'Sleeps';
column spin_gets format 99,999,990      heading 'Spin|Gets';
column misses    format 999,999,990   heading 'Misses';

select b.name                                      name
     , e.gets        - b.gets                      gets
     , e.misses      - b.misses                    misses
     , e.sleeps      - b.sleeps                    sleeps
     , e.spin_gets   - b.spin_gets                 spin_gets
  from stats$latch b
     , stats$latch e
 where b.snap_id         = :bid
   and e.snap_id         = :eid
   and b.dbid            = :dbid
   and e.dbid            = :dbid
   and b.dbid            = e.dbid
   and b.instance_number = :inst_num
   and e.instance_number = :inst_num
   and b.instance_number = e.instance_number
   and b.name            = e.name
   and e.sleeps - b.sleeps > 0
 order by misses desc;



--
--  Latch Miss sources

ttitle lef 'Latch Miss Sources  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
       lef '-> only latches with sleeps are shown' -
       skip 1 -
       lef '-> ordered by name, sleeps desc' -
       skip 2;

column parent        format a24       heading 'Latch Name' trunc;
column where_from    format a26       heading 'Where'      trunc;
column nwmisses      format 99,990    heading 'NoWait|Misses';
column sleeps        format 9,999,990 heading '   Sleeps';
column waiter_sleeps format 999,999    heading 'Waiter|Sleeps';

select e.parent_name                              parent
     , e.where_in_code                            where_from
     , e.nwfail_count  - nvl(b.nwfail_count,0)    nwmisses
     , e.sleep_count   - nvl(b.sleep_count,0)     sleeps
     , e.wtr_slp_count - nvl(b.wtr_slp_count,0)   waiter_sleeps
  from stats$latch_misses_summary b
     , stats$latch_misses_summary e
 where b.snap_id(+)         = :bid
   and e.snap_id            = :eid
   and b.dbid(+)            = :dbid
   and e.dbid               = :dbid
   and b.dbid(+)            = e.dbid
   and b.instance_number(+) = :inst_num
   and e.instance_number    = :inst_num
   and b.instance_number(+) = e.instance_number
   and b.parent_name(+)     = e.parent_name
   and b.where_in_code(+)   = e.where_in_code
   and e.sleep_count        > nvl(b.sleep_count,0)
 order by e.parent_name, sleeps desc;



--
--  Parent Latch

ttitle lef 'Parent Latch Statistics ' -
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
       lef '-> only latches with sleeps are shown' -
       skip 1 -
       lef '-> ordered by name' -
       skip 2;

column name       format a29          heading 'Latch Name' trunc;

select l.name parent
     , lp.gets
     , lp.misses
     , lp.sleeps
     , lp.spin_gets
  from (select e.instance_number, e.dbid, e.snap_id, e.latch#
             , e.gets        - b.gets                      gets
             , e.misses      - b.misses                    misses
             , e.sleeps      - b.sleeps                    sleeps
             , e.spin_gets   - b.spin_gets                 spin_gets
          from stats$latch_parent b
             , stats$latch_parent e
         where b.snap_id         = :bid
           and e.snap_id         = :eid
           and b.dbid            = :dbid
           and e.dbid            = :dbid
           and b.dbid            = e.dbid
           and b.instance_number = :inst_num
           and e.instance_number = :inst_num
           and b.instance_number = e.instance_number
           and b.latch#          = e.latch#
           and e.sleeps - b.sleeps > 0
       )            lp
     , stats$latch  l
 where l.snap_id         = lp.snap_id
   and l.dbid            = lp.dbid
   and l.instance_number = lp.instance_number
   and l.latch#          = lp.latch#
 order by name;



--
--  Latch Children

ttitle lef 'Child Latch Statistics ' -
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
       lef '-> only latches with sleeps/gets > 1/100000 are shown' -
       skip 1 -
       lef '-> ordered by name, gets desc' -
       skip 2;

column name       format a22            heading 'Latch Name' trunc;
column child      format 999999         heading 'Child|Num';
column gets       format 999,999,990    heading 'Get|Requests';
column spin_gets format 99,999,990      heading 'Spin|Gets';

select l.name
     , lc.child
     , lc.gets
     , lc.misses
     , lc.sleeps
     , lc.spin_gets
  from (select /*+ ordered use_hash(b) */
               e.instance_number, e.dbid, e.snap_id, e.latch#
             , e.child#                                    child
             , e.gets        - b.gets                      gets
             , e.misses      - b.misses                    misses
             , e.sleeps      - b.sleeps                    sleeps
             , e.spin_gets   - b.spin_gets                 spin_gets
          from stats$latch_children e
             , stats$latch_children b
         where b.snap_id         = :bid
           and e.snap_id         = :eid
           and b.dbid            = :dbid
           and e.dbid            = :dbid
           and b.dbid            = e.dbid
           and b.instance_number = :inst_num
           and e.instance_number = :inst_num
           and b.instance_number = e.instance_number
           and b.latch#          = e.latch#
           and b.child#          = e.child#
           and e.sleeps - b.sleeps > 0
           and   (e.sleeps - b.sleeps) 
               / (e.gets - b.gets) > .00001
       )            lc
     , stats$latch  l
 where l.snap_id         = lc.snap_id
   and l.dbid            = lc.dbid
   and l.instance_number = lc.instance_number
   and l.latch#          = lc.latch#
 order by name, gets desc;


--
--  Mutex Statistics

ttitle lef 'Mutex Sleep  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
       lef '-> ordered by Wait Time desc' -
       skip 2;

column mux      format a18              heading 'Mutex Type' trunc;
column loc      format a32              heading 'Location'   trunc;
column sleeps   format 9,999,999,990    heading 'Sleeps';
column wt       format 9,999,990.9      heading 'Wait  |Time (s)';

select e.mutex_type                                mux
     , e.location                                  loc
     , e.sleeps    - nvl(b.sleeps, 0)              sleeps
     , (e.wait_time - nvl(b.wait_time, 0))/&ustos  wt
  from stats$mutex_sleep b
     , stats$mutex_sleep e
 where b.snap_id(+)         = :bid
   and e.snap_id            = :eid
   and e.dbid               = :dbid
   and b.dbid(+)            = e.dbid
   and e.instance_number    = :inst_num
   and b.instance_number(+) = e.instance_number
   and b.mutex_type(+)      = e.mutex_type
   and b.location(+)        = e.location
   and e.sleeps - nvl(b.sleeps, 0) > 0
 order by e.wait_time - nvl(b.wait_time, 0) desc;



--
--  Segment Statistics

-- Logical Reads
ttitle lef 'Segments by Logical Reads  ' -
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
           '-> End Segment Logical Reads Threshold: '   format 99999999 eslr -
       skip 1 - 
           '-> Pct Total shows % of logical reads for each top segment compared with total' -
       skip 1 -
           '   logical reads for all segments captured by the Snapshot' -
       skip 2;

column owner           heading "Owner"           format a10    trunc
column tablespace_name heading "Tablespace"      format a10    trunc
column object_name     heading "Object Name"     format a20    trunc
column subobject_name  heading "Subobject|Name"  format a12    trunc
column object_type     heading "Obj.|Type"       format a5     trunc
col    ratio           heading "  Pct|Total"     format a5

column logical_reads heading "Logical|Reads" format 999,999,999

select n.owner
     , n.tablespace_name
     , n.object_name
     , case when length(n.subobject_name) < 11 then
              n.subobject_name
            else
              substr(n.subobject_name,length(n.subobject_name)-9)
       end subobject_name
     , n.object_type
     , r.logical_reads
     , substr(to_char(r.ratio * 100,'999.9MI'), 1, 5) ratio
  from stats$seg_stat_obj n
     , (select *
          from (select e.dataobj#
                     , e.obj#
                     , e.ts#
                     , e.dbid
                     , e.logical_reads - nvl(b.logical_reads, 0) logical_reads
                     , ratio_to_report(e.logical_reads - nvl(b.logical_reads, 0)) over () ratio
                  from stats$seg_stat e
                     , stats$seg_stat b
                 where b.snap_id(+)                              = :bid
                   and e.snap_id                                 = :eid
                   and b.dbid(+)                                 = :dbid
                   and e.dbid                                    = :dbid
                   and b.instance_number(+)                      = :inst_num
                   and e.instance_number                         = :inst_num
                   and b.ts#(+)                                  = e.ts#
                   and b.obj#(+)                                 = e.obj#
                   and b.dataobj#(+)                             = e.dataobj#
                   and e.logical_reads - nvl(b.logical_reads, 0) > 0
                 order by logical_reads desc) d
          where rownum <= &&top_n_segstat) r
 where n.dataobj# = r.dataobj#
   and n.obj#     = r.obj#
   and n.ts#      = r.ts#
   and n.dbid     = r.dbid
   and         7 <= (select snap_level from stats$snapshot where snap_id = :bid)
 order by logical_reads desc;


-- Physical Reads
set newpage 2
ttitle lef 'Segments by Physical Reads  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
           '-> End Segment Physical Reads Threshold: '   espr -
       skip 2

column physical_reads heading "Physical|Reads" format 999,999,999

select n.owner
     , n.tablespace_name
     , n.object_name
     , case when length(n.subobject_name) < 11 then
              n.subobject_name
            else
              substr(n.subobject_name,length(n.subobject_name)-9)
       end subobject_name
     , n.object_type
     , r.physical_reads
     , substr(to_char(r.ratio * 100,'999.9MI'), 1, 5) ratio
  from stats$seg_stat_obj n
     , (select *
          from (select e.dataobj#
                     , e.obj#
                     , e.ts#
                     , e.dbid
                     , e.physical_reads - nvl(b.physical_reads, 0) physical_reads
                     , ratio_to_report(e.physical_reads - nvl(b.physical_reads, 0)) over () ratio
                  from stats$seg_stat e
                     , stats$seg_stat b
                 where b.snap_id(+)                                = :bid
                   and e.snap_id                                   = :eid
                   and b.dbid(+)                                   = :dbid
                   and e.dbid                                      = :dbid
                   and b.instance_number(+)                        = :inst_num
                   and e.instance_number                           = :inst_num
                   and b.ts#(+)                                    = e.ts#
                   and b.obj#(+)                                   = e.obj#
                   and b.dataobj#(+)                               = e.dataobj#
                   and e.physical_reads - nvl(b.physical_reads, 0) > 0
                 order by physical_reads desc) d
          where rownum <= &&top_n_segstat) r
 where n.dataobj# = r.dataobj#
   and n.obj#     = r.obj#
   and n.ts#      = r.ts#
   and n.dbid     = r.dbid
   and         7 <= (select snap_level from stats$snapshot where snap_id = :bid)
 order by physical_reads desc;


-- Row Lock Waits
set newpage 0
ttitle lef 'Segments by Row Lock Waits  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
           '-> End Segment Row Lock Waits Threshold: '   esrl -
       skip 2

column row_lock_waits heading "Row|Lock|Waits" format 999,999,999

select n.owner
     , n.tablespace_name
     , n.object_name
     , case when length(n.subobject_name) < 11 then
              n.subobject_name
            else
              substr(n.subobject_name,length(n.subobject_name)-9)
       end subobject_name
     , n.object_type
     , r.row_lock_waits
     , substr(to_char(r.ratio * 100,'999.9MI'), 1, 5) ratio
  from stats$seg_stat_obj n
     , (select *
          from (select e.dataobj#
                     , e.obj#
                     , e.ts#
                     , e.dbid
                     , e.row_lock_waits - nvl(b.row_lock_waits, 0) row_lock_waits
                     , ratio_to_report(e.row_lock_waits - nvl(b.row_lock_waits, 0)) over () ratio
                  from stats$seg_stat e
                     , stats$seg_stat b
                 where b.snap_id(+)                                = :bid
                   and e.snap_id                                   = :eid
                   and b.dbid(+)                                   = :dbid
                   and e.dbid                                      = :dbid
                   and b.instance_number(+)                        = :inst_num
                   and e.instance_number                           = :inst_num
                   and b.ts#(+)                                    = e.ts#
                   and b.obj#(+)                                   = e.obj#
                   and b.dataobj#(+)                               = e.dataobj#
                   and e.row_lock_waits - nvl(b.row_lock_waits, 0) > 0
                 order by row_lock_waits desc) d
          where rownum <= &&top_n_segstat) r
 where n.dataobj# = r.dataobj#
   and n.obj#     = r.obj#
   and n.ts#      = r.ts#
   and n.dbid     = r.dbid
   and         7 <= (select snap_level from stats$snapshot where snap_id = :bid)
 order by row_lock_waits desc;


-- ITL Waits
set newpage 2
ttitle lef 'Segments by ITL Waits  ' -
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
           '-> End Segment ITL Waits Threshold: '   esiw -
       skip 2

column itl_waits heading "ITL|Waits" format 999,999,999

select n.owner
     , n.tablespace_name
     , n.object_name
     , n.subobject_name
     , n.object_type
     , r.itl_waits
     , substr(to_char(r.ratio * 100,'999.9MI'), 1, 5) ratio
  from stats$seg_stat_obj n
     , (select *
          from (select e.dataobj#
                     , e.obj#
                     , e.ts#
                     , e.dbid
                     , e.itl_waits - nvl(b.itl_waits, 0) itl_waits
                     , ratio_to_report(e.itl_waits - nvl(b.itl_waits, 0)) over () ratio
                  from stats$seg_stat e
                     , stats$seg_stat b
                 where b.snap_id(+)                      = :bid
                   and e.snap_id                         = :eid
                   and b.dbid(+)                         = :dbid
                   and e.dbid                            = :dbid
                   and b.instance_number(+)              = :inst_num
                   and e.instance_number                 = :inst_num
                   and b.ts#(+)                          = e.ts#
                   and b.obj#(+)                         = e.obj#
                   and b.dataobj#(+)                     = e.dataobj#
                   and e.itl_waits - nvl(b.itl_waits, 0) > 0
                 order by itl_waits desc) d
          where rownum <= &&top_n_segstat) r
 where n.dataobj# = r.dataobj#
   and n.obj#     = r.obj#
   and n.ts#      = r.ts#
   and n.dbid     = r.dbid
   and         7 <= (select snap_level from stats$snapshot where snap_id = :bid)
 order by itl_waits desc;


-- Buffer Busy Waits
set newpage 2
ttitle lef 'Segments by Buffer Busy Waits  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
           '-> End Segment Buffer Busy Waits Threshold: '   esbb -
       skip 2

column buffer_busy_waits heading "Buffer|Busy|Waits" format 999,999,999

select n.owner
     , n.tablespace_name
     , n.object_name
     , case when length(n.subobject_name) < 11 then
              n.subobject_name
            else
              substr(n.subobject_name,length(n.subobject_name)-9)
       end subobject_name
     , n.object_type
     , r.buffer_busy_waits
     , substr(to_char(r.ratio * 100,'999.9MI'), 1, 5) ratio
  from stats$seg_stat_obj n
     , (select *
          from (select e.dataobj#
                     , e.obj#
                     , e.ts#
                     , e.dbid
                     , e.buffer_busy_waits - nvl(b.buffer_busy_waits, 0) buffer_busy_waits
                     , ratio_to_report(e.buffer_busy_waits - nvl(b.buffer_busy_waits, 0)) over () ratio
                  from stats$seg_stat e
                     , stats$seg_stat b
                 where b.snap_id(+)                                      = :bid
                   and e.snap_id                                         = :eid
                   and b.dbid(+)                                         = :dbid
                   and e.dbid                                            = :dbid
                   and b.instance_number(+)                              = :inst_num
                   and e.instance_number                                 = :inst_num
                   and b.ts#(+)                                          = e.ts#
                   and b.obj#(+)                                         = e.obj#
                   and b.dataobj#(+)                                     = e.dataobj#
                   and e.buffer_busy_waits - nvl(b.buffer_busy_waits, 0) > 0
                 order by buffer_busy_waits desc) d
          where rownum <= &&top_n_segstat) r
 where n.dataobj# = r.dataobj#
   and n.obj#     = r.obj#
   and n.ts#      = r.ts#
   and n.dbid     = r.dbid
   and         7 <= (select snap_level from stats$snapshot where snap_id = :bid)
 order by buffer_busy_waits desc;


-- GC Buffer Busy Waits
set newpage 0
ttitle lef 'Segments by Global Cache Buffer Busy Waits  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
           '-> There is no specific Threshold for Segment GC Buffer Busy Waits'-
       skip 2

column gc_buffer_busy heading "GC Buffer|Busy|Waits" format 999,999,999

select n.owner
     , n.tablespace_name
     , n.object_name
     , case when length(n.subobject_name) < 11 then
              n.subobject_name
            else
              substr(n.subobject_name,length(n.subobject_name)-9)
       end subobject_name
     , n.object_type
     , r.gc_buffer_busy
     , substr(to_char(r.ratio * 100,'999.9MI'), 1, 5) ratio
  from stats$seg_stat_obj n
     , (select *
          from (select e.dataobj#
                     , e.obj#
                     , e.ts#
                     , e.dbid
                     , e.gc_buffer_busy - nvl(b.gc_buffer_busy, 0) gc_buffer_busy
                     , ratio_to_report(e.gc_buffer_busy - nvl(b.gc_buffer_busy, 0)) over () ratio
                  from stats$seg_stat e
                     , stats$seg_stat b
                 where b.snap_id(+)                                      = :bid
                   and e.snap_id                                         = :eid
                   and b.dbid(+)                                         = :dbid
                   and e.dbid                                            = :dbid
                   and b.instance_number(+)                              = :inst_num
                   and e.instance_number                                 = :inst_num
                   and b.ts#(+)                                          = e.ts#
                   and b.obj#(+)                                         = e.obj#
                   and b.dataobj#(+)                                     = e.dataobj#
                   and e.gc_buffer_busy - nvl(b.gc_buffer_busy, 0) > 0
                 order by gc_buffer_busy desc) d
          where rownum <= &&top_n_segstat) r
 where n.dataobj# = r.dataobj#
   and n.obj#     = r.obj#
   and n.ts#      = r.ts#
   and n.dbid     = r.dbid
   and         7 <= (select snap_level from stats$snapshot where snap_id = :bid)
 order by gc_buffer_busy desc;


-- CR Blocks Received (was Served in versions prior to 10g)
set newpage 2
ttitle lef 'Segments by CR Blocks Received  ' -
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
           '-> End Global Cache CR Blocks Received Threshold: '   ecrb -
       skip 2

column cr_blocks_received heading "CR|Blocks|Recevd" format 999,999,999

select n.owner
     , n.tablespace_name
     , n.object_name
     , case when length(n.subobject_name) < 11 then
              n.subobject_name
            else
              substr(n.subobject_name,length(n.subobject_name)-9)
       end subobject_name
     , n.object_type
     , r.cr_blocks_received
     , substr(to_char(r.ratio * 100,'999.9MI'), 1, 5) ratio
  from stats$seg_stat_obj n
     , (select *
          from (select e.dataobj#
                     , e.obj#
                     , e.ts#
                     , e.dbid
                     , e.gc_cr_blocks_received-nvl(b.gc_cr_blocks_received, 0) cr_blocks_received
                     , ratio_to_report(e.gc_cr_blocks_received - nvl(b.gc_cr_blocks_received, 0)) over () ratio
                  from stats$seg_stat e
                     , stats$seg_stat b
                 where b.snap_id(+)                                      = :bid
                   and e.snap_id                                         = :eid
                   and b.dbid(+)                                         = :dbid
                   and e.dbid                                            = :dbid
                   and b.instance_number(+)                              = :inst_num
                   and e.instance_number                                 = :inst_num
                   and b.ts#(+)                                          = e.ts#
                   and b.obj#(+)                                         = e.obj#
                   and b.dataobj#(+)                                     = e.dataobj#
                   and e.gc_cr_blocks_received-nvl(b.gc_cr_blocks_received,0)>0
                 order by cr_blocks_received desc) d
          where rownum <= &&top_n_segstat) r
 where n.dataobj# = r.dataobj#
   and n.obj#     = r.obj#
   and n.ts#      = r.ts#
   and n.dbid     = r.dbid
   and         7 <= (select snap_level from stats$snapshot where snap_id = :bid)
   and :para      ='YES'
 order by cr_blocks_received desc;


-- Current Blocks Received (was Served in versions prior to 10g)
set newpage 2
ttitle lef 'Segments By Current Blocks Received  ' -
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
           '-> End Global Cache CU Blocks Received Threshold: '   ecub -
       skip 2

column cu_blocks_received heading "CU|Blocks|Recevd" format 999,999,999

select n.owner
     , n.tablespace_name
     , n.object_name
     , case when length(n.subobject_name) < 11 then
              n.subobject_name
            else
              substr(n.subobject_name,length(n.subobject_name)-9)
       end subobject_name
     , n.object_type
     , r.cu_blocks_received
     , substr(to_char(r.ratio * 100,'999.9MI'), 1, 5) ratio
  from stats$seg_stat_obj n
     , (select *
          from (select e.dataobj#
                     , e.obj#
                     , e.ts#
                     , e.dbid
                     , e.gc_current_blocks_received-nvl(b.gc_current_blocks_received, 0) cu_blocks_received
                     , ratio_to_report(e.gc_current_blocks_received - nvl(b.gc_current_blocks_received, 0)) over () ratio
                  from stats$seg_stat e
                     , stats$seg_stat b
                 where b.snap_id(+)                                      = :bid
                   and e.snap_id                                         = :eid
                   and b.dbid(+)                                         = :dbid
                   and e.dbid                                            = :dbid
                   and b.instance_number(+)                              = :inst_num
                   and e.instance_number                                 = :inst_num
                   and b.ts#(+)                                          = e.ts#
                   and b.obj#(+)                                         = e.obj#
                   and b.dataobj#(+)                                     = e.dataobj#
                   and e.gc_current_blocks_received-nvl(b.gc_current_blocks_received,0)>0
                 order by cu_blocks_received desc) d
          where rownum <= &&top_n_segstat) r
 where n.dataobj# = r.dataobj#
   and n.obj#     = r.obj#
   and n.ts#      = r.ts#
   and n.dbid     = r.dbid
   and         7 <= (select snap_level from stats$snapshot where snap_id = :bid)
   and :para      ='YES'
 order by cu_blocks_received desc;


set newpage 0
--
--  Dictionary Cache

ttitle lef 'Dictionary Cache Stats  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
       lef '->"Pct Misses"  should be very low (< 2% in most cases)'-
       skip 1 -
       lef '->"Final Usage" is the number of cache entries being used in End Snapshot'-
       skip 2;

column param    format a25              heading 'Cache'  trunc;
column gets     format 999,999,990      heading 'Get|Requests';
column getm     format 990.9            heading 'Pct|Miss';
column scans    format 99,990           heading 'Scan|Reqs';
column scanm    format 90.9             heading 'Pct|Miss';
column mods     format  999,990         heading 'Mod|Reqs';
column usage    format 9,999,990        heading 'Final|Usage';

select lower(b.parameter)                                        param
     , e.gets - b.gets                                           gets
     , to_number(decode(e.gets,b.gets,null,
       (e.getmisses - b.getmisses) * 100/(e.gets - b.gets)))     getm
     , e.scans - b.scans                                         scans
     , to_number(decode(e.scans,b.scans,null,
       (e.scanmisses - b.scanmisses) * 100/(e.scans - b.scans))) scanm
     , e.modifications - b.modifications                         mods
     , e.usage                                                   usage
  from stats$rowcache_summary b
     , stats$rowcache_summary e
 where b.snap_id         = :bid
   and e.snap_id         = :eid
   and b.dbid            = :dbid
   and e.dbid            = :dbid
   and b.dbid            = e.dbid
   and b.instance_number = :inst_num
   and e.instance_number = :inst_num
   and b.instance_number = e.instance_number
   and b.parameter       = e.parameter
   and e.gets - b.gets   > 0
 order by param;


ttitle off;
set newpage 2;

column dreq     format 999,999,999 heading 'GES|Requests'
column dcon     format 999,999,999 heading 'GES|Conflicts'
column drel     format 999,999,999 heading 'GES|Releases'

select lower(b.parameter)                                        param
     , e.dlm_requests  - b.dlm_requests                          dreq
     , e.dlm_conflicts - b.dlm_conflicts                         dcon
     , e.dlm_releases  - b.dlm_releases                          drel
  from stats$rowcache_summary b
     , stats$rowcache_summary e
 where b.snap_id                       = :bid
   and e.snap_id                       = :eid
   and b.dbid                          = :dbid
   and e.dbid                          = :dbid
   and b.dbid                          = e.dbid
   and b.instance_number               = :inst_num
   and e.instance_number               = :inst_num
   and b.instance_number               = e.instance_number
   and b.parameter                     = e.parameter
   and e.dlm_requests - b.dlm_requests > 0
   and :para                           = 'YES'
 order by param;



--
--  Library Cache

set newpage 2;
ttitle lef 'Library Cache Activity  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
           '->"Pct Misses"  should be very low  ' skip 2;

column namespace                      heading 'Namespace';
column gets     format 999,999,990    heading 'Get|Requests';
column pins     format 9,999,999,990  heading 'Pin|Requests' just c;
column getm     format 990.9          heading 'Pct|Miss' just c;
column pinm     format 990.9          heading 'Pct|Miss' just c;
column reloads  format 9,999,990      heading 'Reloads';
column inv      format 999,990        heading 'Invali-|dations';

select e.namespace
     , e.gets - b.gets                                         gets  
     , to_number(decode(e.gets,b.gets,null,
       100 - (e.gethits - b.gethits) * 100/(e.gets - b.gets))) getm
     , e.pins - b.pins                                         pins  
     , to_number(decode(e.pins,b.pins,null,
       100 - (e.pinhits - b.pinhits) * 100/(e.pins - b.pins))) pinm
     , e.reloads - b.reloads                                   reloads
     , e.invalidations - b.invalidations                       inv
  from stats$librarycache b
     , stats$librarycache e
 where b.snap_id         = :bid   
   and e.snap_id         = :eid
   and e.dbid            = :dbid
   and b.dbid            = e.dbid
   and e.instance_number = :inst_num
   and b.instance_number = e.instance_number
   and b.namespace       = e.namespace
   and e.gets - b.gets   > 0;



ttitle off;
set newpage 2;

column dlreq    format 999,999,999      heading 'GES Lock|Requests';
column dpreq    format 999,999,999      heading 'GES Pin|Requests';
column dprel    format 999,999,999      heading 'GES Pin|Releases';
column direq    format  99,999,999      heading 'GES Inval|Requests'
column dinv     format  99,999,999      heading 'GES Invali-|dations';

select e.namespace
     , e.dlm_lock_requests - b.dlm_lock_requests               dlreq
     , e.dlm_pin_requests  - b.dlm_pin_requests                dpreq
     , e.dlm_pin_releases  - b.dlm_pin_releases                dprel
     , e.dlm_invalidation_requests - b.dlm_invalidation_requests direq
     , e.dlm_invalidations - b.dlm_invalidations               dinv
  from stats$librarycache b
     , stats$librarycache e
 where b.snap_id          = :bid   
   and e.snap_id          = :eid
   and e.dbid             = :dbid
   and b.dbid             = e.dbid
   and e.instance_number  = :inst_num
   and b.instance_number  = e.instance_number
   and b.namespace        = e.namespace
   and e.gets - b.gets    > 0
   and :para              = 'YES';

set newpage 0;




--
--  Miscellaneous GES RAC Statistics

ttitle lef 'Global Enqueue Stats  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 2;

column st       format a33              heading 'Statistic' trunc;
column dif      format 999,999,999,990  heading 'Total';
column ps       format 9,999,990.9      heading 'per Second';
column pt       format 9,999,990.9      heading 'per Trans';

select b.name                           st
     , e.value - b.value                dif
     , round(e.value - b.value)/:ela    ps
     , round(e.value - b.value)/:tran   pt
  from stats$dlm_misc b
     , stats$dlm_misc e
 where b.snap_id         = :bid
   and e.snap_id         = :eid
   and b.instance_number = :inst_num
   and e.instance_number = :inst_num
   and b.dbid            = :dbid
   and e.dbid            = :dbid
   and e.statistic#      = b.statistic#
   and :para             = 'YES'
 order by b.name;


--
-- CR Blocks Served Statistics (RAC)

ttitle lef 'Global CR Served Stats  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 2;

set heading off;

column nl format a30 newline
column val format 9,999,999,999,990

select 'Statistic                                   Total'  
     , '------------------------------'                    nl
     , '------------------'
     , 'CR Block Requests             '                    nl
     , e.cr_requests - b.cr_requests                       val
     , 'CURRENT Block Requests        '                    nl
     , e.current_requests - b.current_requests             val
     , 'Data Block Requests           '                    nl
     , e.data_requests - b.data_requests                   val
     , 'Undo Block Requests           '                    nl
     , e.undo_requests - b.undo_requests                   val
     , 'TX Block Requests             '                    nl
     , e.tx_requests - b.tx_requests                       val
     , 'Current Results               '                    nl
     , e.current_results - b.current_results               val
     , 'Private results               '                    nl
     , e.private_results - b.private_results               val
     , 'Zero Results                  '                    nl
     , e.zero_results - b.zero_results                     val
     , 'Disk Read Results             '                    nl
     , e.disk_read_results -b.disk_read_results            val
     , 'Fail Results                  '                    nl
     , e.fail_results - b.fail_results                     val
     , 'Fairness Down Converts        '                    nl
     , e.fairness_down_converts - b.fairness_down_converts val
     , 'Fairness Clears               '                    nl
     , e.fairness_clears - b.fairness_clears               val
     , 'Free GC Elements              '                    nl
     , e.free_gc_elements - b.free_gc_elements             val
     , 'Flushes                       '                    nl
     , e.flushes - b.flushes                               val
     , 'Flushes Queued                '                    nl
     , e.flushes_queued - b.flushes_queued                 val
     , 'Flush Queue Full              '                    nl
     , e.flush_queue_full - b.flush_queue_full             val
     , 'Flush Max Time (us)           '                    nl
     , e.flush_max_time - b.flush_max_time                 val
     , 'Light Works                   '                    nl
     , e.light_works - b.light_works                       val
     , 'Errors                        '                    nl
     , e.errors - b.errors                                 val
  from stats$cr_block_server b
     , stats$cr_block_server e
 where b.snap_id         = :bid
   and e.snap_id         = :eid
   and b.instance_number = :inst_num
   and e.instance_number = :inst_num
   and b.dbid            = :dbid
   and e.dbid            = :dbid
   and :para             = 'YES';

set newpage 2;

--
-- CURRENT Blocks Served Statistics (RAC)

ttitle lef 'Global CURRENT Served Stats  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
           '-> Pins    = CURRENT Block Pin Operations' -
       skip 1 -
           '-> Flushes = Redo Flush before CURRENT Block Served Operations' -
       skip 1 -
           '-> Writes  = CURRENT Block Fusion Write Operations' -
       skip 2;

column tot      format 999,999,990
column stat     newline

select 'Statistic  '
     , '      Total'
     , '  % <1ms'
     , ' % <10ms'
     , '% <100ms'
     , '   % <1s'
     , '  % <10s'
     , '----------- ----------- -------- -------- -------- -------- --------'
     , 'Pins      ' stat
     , pins         tot
     , lpad(to_char(decode(pins,0,0,100*pin1/pins),'990.99'),8,' ')
     , lpad(to_char(decode(pins,0,0,100*pin10/pins),'990.99'),8,' ')
     , lpad(to_char(decode(pins,0,0,100*pin100/pins),'990.99'),8,' ')
     , lpad(to_char(decode(pins,0,0,100*pin1000/pins),'990.99'),8,' ')
     , lpad(to_char(decode(pins,0,0,100*pin10000/pins),'990.99'),8,' ')
     , 'Flushes   ' stat
     , flushes      tot
     , lpad(to_char(decode(flushes,0,0,100*flush1/flushes),'990.99'),8,' ')
     , lpad(to_char(decode(flushes,0,0,100*flush10/flushes),'990.99'),8,' ')
     , lpad(to_char(decode(flushes,0,0,100*flush100/flushes),'990.99'),8,' ')
     , lpad(to_char(decode(flushes,0,0,100*flush1000/flushes),'990.99'),8,' ')
     , lpad(to_char(decode(flushes,0,0,100*flush10000/flushes),'990.99'),8,' ')
     , 'Writes    ' stat
     , writes       tot
     , lpad(to_char(decode(writes,0,0,100*write1/writes),'990.99'),8,' ')
     , lpad(to_char(decode(writes,0,0,100*write10/writes),'990.99'),8,' ')
     , lpad(to_char(decode(writes,0,0,100*write100/writes),'990.99'),8,' ')
     , lpad(to_char(decode(writes,0,0,100*write1000/writes),'990.99'),8,' ')
     , lpad(to_char(decode(writes,0,0,100*write10000/writes),'990.99'),8,' ')
  from (select (e.pin1+e.pin10+e.pin100+e.pin1000+e.pin10000 -
                (b.pin1+b.pin10+b.pin100+b.pin1000+b.pin10000)
               )                               pins
             , e.pin1 - b.pin1                 pin1
             , e.pin10 - b.pin10               pin10
             , e.pin100 - b.pin100             pin100
             , e.pin1000 - b.pin1000           pin1000
             , e.pin10000 - b.pin10000         pin10000
             , (e.flush1+e.flush10+e.flush100+e.flush1000+e.flush10000 -
                (b.flush1+b.flush10+b.flush100+b.flush1000+b.flush10000)
               )                               flushes
             , e.flush1 - b.flush1             flush1
             , e.flush10 - b.flush10           flush10
             , e.flush100 - b.flush100         flush100
             , e.flush1000 - b.flush1000       flush1000
             , e.flush10000 - b.flush10000     flush10000
             , (e.write1+e.write10+e.write100+e.write1000+e.write10000 -
                (b.write1+b.write10+b.write100+b.write1000+b.write10000)
               )                               writes
             , e.write1 - b.write1             write1
             , e.write10 - b.write10           write10
             , e.write100 - b.write100         write100
             , e.write1000 - b.write1000       write1000
             , e.write10000 - b.write10000     write10000
          from stats$current_block_server b
             , stats$current_block_server e
         where b.snap_id         = :bid
           and e.snap_id         = :eid
           and b.instance_number = :inst_num
           and e.instance_number = :inst_num
           and b.dbid            = :dbid
           and e.dbid            = :dbid
           and :para             = 'YES');

--
-- Cache Transfer Statistics (RAC)

ttitle lef 'Global Cache Transfer Stats  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
       lef '-> Immediate  (Immed) - Block Transfer NOT impacted by Remote Processing Delays' -
       skip 1 -
       lef '   Busy        (Busy) - Block Transfer impacted by Remote Contention' -
       skip 1 -
       lef '   Congested (Congst) - Block Transfer impacted by Remote System Load' -
       skip 1 -
           '-> ordered by CR + Current Blocks Received desc' -
       skip 2 -
           '              -------------- CR -------------  ----------- Current -----------';

set heading on;

column inst     format 990         heading 'Inst|No'
column class    format a8          heading 'Block|Class' trunc
column totcr    format 99,999,990  heading 'Blocks|Received'
column totcu    format 99,999,990  heading 'Blocks|Received'
column blkimm   format 999.9       heading '%|Immed'
column blkbus   format 999.9       heading '%|Busy'
column blkcgt   format 999.9       heading '%|Congst'

--
-- Transfer Cache Statistics detailed per instance
-- Report only if define variable cache_xfer_per_instance = 'Y'

with instance_cache_transfer as (
  select snap_id
       , instance
       , case when class in ('data block', 'undo header', 'undo block')
                then class
              else 'others' end as class
       , sum(cr_block)                                                   cr_block
       , sum(cr_busy)                                                    cr_busy
       , sum(cr_congested)                                               cr_congested
       , sum(current_block)                                              current_block
       , sum(current_busy)                                               current_busy
       , sum(current_congested)                                          current_congested
       , sum(cr_block) + sum(cr_busy) + sum(cr_congested)                totcr
       , sum(current_block) + sum(current_busy) + sum(current_congested) totcu
    from stats$instance_cache_transfer
   where instance_number             = :inst_num
     and dbid                        = :dbid
     and '&&cache_xfer_per_instance' = 'Y'
     and :para                       = 'YES'
   group by snap_id
       , instance
       , case when class in ('data block', 'undo header', 'undo block')
                then class
              else 'others' end)
select e.instance                 inst
     , e.class                    class
     , e.totcr - nvl(b.totcr , 0) totcr
     , decode(e.totcr-nvl(b.totcr, 0), 0, to_number(NULL), (e.cr_block-nvl(b.cr_block, 0))*100/(e.totcr-nvl(b.totcr, 0)))    blkimm
     , decode(e.totcr-nvl(b.totcr, 0), 0, to_number(NULL), (e.cr_busy -nvl(b.cr_busy,  0))*100/(e.totcr-nvl(b.totcr, 0)))    blkbus
     , decode(e.totcr-nvl(b.totcr,0),0,to_number(NULL),(e.cr_congested-nvl(b.cr_congested, 0))*100/(e.totcr-nvl(b.totcr,0))) blkcgt
     , e.totcu - nvl(b.totcu , 0) totcu
     , decode(e.totcu-nvl(b.totcu, 0), 0, to_number(NULL), (e.current_block-nvl(b.current_block, 0))*100/(e.totcu-nvl(b.totcu, 0)))    blkimm
     , decode(e.totcu-nvl(b.totcu, 0), 0, to_number(NULL), (e.current_busy -nvl(b.current_busy,  0))*100/(e.totcu-nvl(b.totcu, 0)))    blkbus
     , decode(e.totcu-nvl(b.totcu,0),0,to_number(NULL),(e.current_congested-nvl(b.current_congested, 0))*100/(e.totcu-nvl(b.totcu,0))) blkcgt
  from (select * from instance_cache_transfer
         where snap_id      = :bid) b
     , (select * from instance_cache_transfer
         where snap_id      = :eid) e
 where b.class(+)           = e.class
   and b.instance(+)        = e.instance
   and e.totcr + e.totcu - nvl(b.totcr, 0) - nvl(b.totcu, 0) > 0
 order by totcr + totcu desc;


--
-- Transfer Cache Statistics aggregated per class
-- Report only if define variable cache_xfer_per_instance = 'N'

column class    format a12

with class_cache_transfer as (
  select snap_id
       , case when class in ('data block', 'undo header', 'undo block')
                then class
              else 'others' end as class
       , sum(cr_block)                                                   cr_block
       , sum(cr_busy)                                                    cr_busy
       , sum(cr_congested)                                               cr_congested
       , sum(current_block)                                              current_block
       , sum(current_busy)                                               current_busy
       , sum(current_congested)                                          current_congested
       , sum(cr_block) + sum(cr_busy) + sum(cr_congested)                totcr
       , sum(current_block) + sum(current_busy) + sum(current_congested) totcu
    from stats$instance_cache_transfer
   where instance_number             = :inst_num
     and dbid                        = :dbid
     and '&&cache_xfer_per_instance' = 'N'
     and :para                       = 'YES'
   group by snap_id
       , case when class in ('data block', 'undo header', 'undo block')
                then class
                else 'others' end)
select e.class
     , e.totcr              - nvl(b.totcr            , 0) totcr
     , decode(e.totcr-nvl(b.totcr, 0), 0, to_number(NULL), (e.cr_block-nvl(b.cr_block, 0))*100/(e.totcr-nvl(b.totcr, 0)))    blkimm
     , decode(e.totcr-nvl(b.totcr, 0), 0, to_number(NULL), (e.cr_busy-nvl(b.cr_busy, 0))*100/(e.totcr-nvl(b.totcr, 0)))      blkbus
     , decode(e.totcr-nvl(b.totcr,0),0,to_number(NULL),(e.cr_congested-nvl(b.cr_congested, 0))*100/(e.totcr-nvl(b.totcr,0))) blkcgt
     , e.totcu              - nvl(b.totcu            , 0) totcu
     , decode(e.totcu-nvl(b.totcu, 0), 0, to_number(NULL), (e.current_block-nvl(b.current_block, 0))*100/(e.totcu-nvl(b.totcu, 0)))    blkimm
     , decode(e.totcu-nvl(b.totcu, 0), 0, to_number(NULL), (e.current_busy-nvl(b.current_busy, 0))*100/(e.totcu-nvl(b.totcu, 0)))      blkbus
     , decode(e.totcu-nvl(b.totcu,0),0,to_number(NULL),(e.current_congested-nvl(b.current_congested, 0))*100/(e.totcu-nvl(b.totcu,0))) blkcgt
  from (select * from class_cache_transfer
         where snap_id         = :bid) b
     , (select * from class_cache_transfer
         where snap_id         = :eid) e
 where b.class(+)           = e.class
   and (e.totcr + e.totcu - nvl(b.totcr, 0) - nvl(b.totcu, 0)) > 0
 order by totcr + totcu desc;

set newpage 0;


--
-- Remastering Stats

set heading off;

ttitle lef 'Dynamic Remastering Stats  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 2;

column numX  format 9,999,999,990
column numXX format    99,999,990.9

select '    Remaster Operations:'                                    ch25n
     , e.remaster_ops            - nvl(b.remaster_ops, 0)            numX
     , '  Remaster Time(s):'                                         ch20
     , (e.remaster_time    - nvl(b.remaster_time, 0))/&cstos         numXX
     , '     Remastered Objects:'                                    ch25n
     , e.remastered_objects      - nvl(b.remastered_objects, 0)      numX
     , '   Quiesce Time(s):'                                         ch20
     , (e.quiesce_time     - nvl(b.quiesce_time, 0))/&cstos          numXX
     , ' Affinity Objects (Beg):'                                    ch25n
     , b.current_objects                                             numX
     , '    Freeze Time(s):'                                         ch20
     , (e.freeze_time      - nvl(b.freeze_time, 0))/&cstos           numXX
     , ' Affinity Objects (End):'                                    ch25n
     , e.current_objects                                             numX
     , '   Cleanup Time(s):'                                         ch20
     , (e.cleanup_time     - nvl(b.cleanup_time, 0))/&cstos          numXX
     , '    Replayed Locks Sent:'                                    ch25n
     , e.replayed_locks_sent     - nvl(b.replayed_locks_sent, 0)     numX
     , '    Replay Time(s):'                                         ch20
     , (e.replay_time      - nvl(b.replay_time, 0))/&cstos           numXX
     , '   Replayed Locks Recvd:'                                    ch25n
     , e.replayed_locks_received - nvl(b.replayed_locks_received, 0) numX
     , '  Fixwrite Time(s):'                                         ch20
     , (e.fixwrite_time    - nvl(b.fixwrite_time, 0))/&cstos         numXX
     , '      Resources Cleaned:'                                    ch25n
     , e.resources_cleaned - nvl(b.resources_cleaned, 0)             numX
     , '      Sync Time(s):'                                         ch20
     , (e.sync_time        - nvl(b.sync_time, 0))/&cstos             numXX
  from stats$dynamic_remaster_stats b
     , stats$dynamic_remaster_stats e
 where b.snap_id(+)         = :bid
   and e.snap_id            = :eid
   and e.dbid               = :dbid
   and b.dbid(+)            = e.dbid
   and e.instance_number    = :inst_num
   and b.instance_number(+) = e.instance_number
   and e.remaster_ops - nvl(b.remaster_ops, 0) > 0;

set heading on;



--
-- Streams

ttitle lef 'Streams Capture  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
       lef '-> * indicates Capture process (re)started between Begin/End snaps' -
       skip 1 -
       lef '-> Top &&streams_top_n ordered by Messages Queued desc' -
       skip 2;

col capture_name            format a20 trunc   heading 'Capture Name'
col a                                          heading '*'
col capture_rate            format   9,999     heading 'Captured|Msg/s'     just c
col enqueue_rate            format   9,999     heading 'Enq|Msg/s'          just c
col pct_capture             format     999     heading 'Capt|Time %'        just c
col pct_lcr                 format     999     heading 'Msg|Creatn|Time %'   just c
col pct_rule                format     999     heading 'Rule|Time %'        just c
col pct_enqueue             format     999     heading 'Enq|Time %'         just c
col pct_redo_wait           format     999     heading 'Redo|Wait|Time %'   just c
col pct_pause               format     999     heading 'Pause|Time %'       just c

select capture_name
     , a
     , total_messages_captured/:ela capture_rate
     , total_messages_enqueued/:ela enqueue_rate
     ,   elapsed_capture_time 
       / ( elapsed_capture_time + elapsed_lcr_time + elapsed_rule_time + 
           elapsed_enqueue_time + elapsed_redo_wait_time + elapsed_pause_time +
           .0000001
         ) 
       * 100 pct_capture
     ,   elapsed_lcr_time 
       / (elapsed_capture_time + elapsed_lcr_time + elapsed_rule_time + 
          elapsed_enqueue_time + elapsed_redo_wait_time + elapsed_pause_time + 
          .0000001
         ) 
       * 100 pct_lcr
     ,   elapsed_rule_time
       / (elapsed_capture_time + elapsed_lcr_time + elapsed_rule_time + 
          elapsed_enqueue_time + elapsed_redo_wait_time + elapsed_pause_time +
          .0000001) 
       * 100 pct_rule
     ,   elapsed_enqueue_time
       / (elapsed_capture_time + elapsed_lcr_time + elapsed_rule_time + 
          elapsed_enqueue_time + elapsed_redo_wait_time + elapsed_pause_time +
          .0000001) 
       * 100 pct_enqueue
     ,   elapsed_redo_wait_time
       / (elapsed_capture_time + elapsed_lcr_time + elapsed_rule_time + 
          elapsed_enqueue_time + elapsed_redo_wait_time + elapsed_pause_time + 
          .0000001) 
       * 100 pct_redo_wait
     ,   elapsed_pause_time
       / (elapsed_capture_time + elapsed_lcr_time + elapsed_rule_time + 
          elapsed_enqueue_time + elapsed_redo_wait_time + elapsed_pause_time +
          .0000001) 
       * 100 pct_pause
  from (select e.capture_name
             , decode( e.startup_time, b.startup_time, null, '*')              a
             , e.total_messages_captured  - nvl(b.total_messages_captured, 0)  total_messages_captured
             , e.total_messages_enqueued  - nvl(b.total_messages_enqueued, 0)  total_messages_enqueued
             , e.elapsed_capture_time     - nvl(b.elapsed_capture_time ,0)     elapsed_capture_time
             , e.elapsed_lcr_time         - nvl(b.elapsed_lcr_time,0)          elapsed_lcr_time
             , e.elapsed_rule_time        - nvl(b.elapsed_rule_time, 0)        elapsed_rule_time
             , e.elapsed_enqueue_time     - nvl(b.elapsed_enqueue_time,0)      elapsed_enqueue_time
             , e.elapsed_redo_wait_time   - nvl(b.elapsed_redo_wait_time,0)    elapsed_redo_wait_time
             , e.elapsed_pause_time       - nvl(b.elapsed_pause_time,0)        elapsed_pause_time
          from stats$streams_capture b
             , stats$streams_capture e
         where b.snap_id         (+)= :bid
           and e.snap_id            = :eid
           and e.dbid               = :dbid
           and b.dbid            (+)= e.dbid
           and e.instance_number    = :inst_num
           and b.instance_number (+)= e.instance_number
           and b.capture_name    (+)= e.capture_name
           and b.startup_time    (+)= e.startup_time
         order by e.total_messages_enqueued desc
       )
 where rownum <= &&streams_top_n;


set newpage 2;

ttitle lef 'Propagation Sender  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
       lef '-> * indicates Sender process (re)started between Begin/End snaps' -
       skip 1 -
       lef '-> Top &&streams_top_n ordered by Messages desc' -
       skip 2;

col qname                   format a22   trunc heading 'Queue'
col a                                          heading '*'
col destination             format a22   trunc heading 'Destination'
col msgs_per_sec            format      99,999 heading 'Msg/s'         just c
col kbyte_per_sec           format      99,999 heading 'KB/s'          just c
col pct_dequeue             format         999 heading 'Deq|Time|%'    just c
col pct_pickle              format         999 heading 'Pickle|Time|%' just c
col pct_propagation         format         999 heading 'Prop|Time|%'   just c

select qname
     , dblink                                            destination
     , a
     , total_msgs/:ela                                   msgs_per_sec
     , total_bytes/1024/:ela                             kbyte_per_sec
     ,  elapsed_dequeue_time
      / (elapsed_dequeue_time + elapsed_pickle_time + 
         elapsed_propagation_time + .0000001
        ) 
      * 100                                              pct_dequeue
     ,   elapsed_pickle_time
       / (elapsed_dequeue_time + elapsed_pickle_time + 
          elapsed_propagation_time + .0000001
         ) 
      * 100                                              pct_pickle
     ,   elapsed_propagation_time
       / (elapsed_dequeue_time + elapsed_pickle_time + 
          elapsed_propagation_time + .0000001
         ) 
       * 100                                             pct_propagation
  from (select e.queue_schema||'.'||e.queue_name                  qname
             , e.dblink                                           dblink
             , decode(e.startup_time, b.startup_time, null, '*')  a
             , e.total_msgs               - nvl(b.total_msgs, 0)  total_msgs
             , e.total_bytes              - nvl(b.total_bytes, 0) total_bytes
             , e.elapsed_dequeue_time     - nvl(b.elapsed_dequeue_time ,0)     elapsed_dequeue_time
             , e.elapsed_pickle_time      - nvl(b.elapsed_pickle_time,0)       elapsed_pickle_time
             , e.elapsed_propagation_time - nvl(b.elapsed_propagation_time, 0) elapsed_propagation_time
          from stats$propagation_sender b
             , stats$propagation_sender e
         where b.snap_id         (+) = :bid
           and e.snap_id             = :eid
           and e.dbid                = :dbid
           and b.dbid            (+) = e.dbid
           and e.instance_number     = :inst_num
           and b.instance_number (+) = e.instance_number
           and b.queue_schema    (+) = e.queue_schema
           and b.queue_name      (+) = e.queue_name
           and b.dblink          (+) = e.dblink
           and b.dst_queue_schema(+) = e.dst_queue_schema
           and b.dst_queue_name  (+) = e.dst_queue_name
           and b.startup_time    (+) = e.startup_time
          order by e.total_msgs desc
       )
 where rownum <= &&streams_top_n;

set newpage 0;



ttitle lef 'Propagation Receiver  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
       lef '-> * indicates Receiver process (re)started between Begin/End snaps' -
       skip 1 -
       lef '-> Top &&streams_top_n ordered by Source Queue Name, Source DB' -
       skip 2;

col src_queue_name      format a25         heading 'Source|Queue'
col src_dbname          format a35         heading 'Source|DB Name'
col a                                      heading '*'
col pct_unpickle        format          99 heading 'Un-|pickle|Time %' just c
col pct_rule            format          99 heading 'Rule|Time|%'       just c
col pct_enqueue         format          99 heading 'Enq|Time|%'        just c

select src_queue_name
     , src_dbname
     , a
     ,   elapsed_unpickle_time
       / (elapsed_unpickle_time + elapsed_rule_time + elapsed_enqueue_time + + 
          .0000001
         ) 
       * 100                               pct_unpickle
     ,   elapsed_rule_time
       / (elapsed_unpickle_time + elapsed_rule_time + elapsed_enqueue_time + + 
          .0000001
         ) 
       * 100                               pct_rule
     ,   elapsed_enqueue_time
       / (elapsed_unpickle_time + elapsed_rule_time + elapsed_enqueue_time + +
         .0000001
         )
       * 100                               pct_enqueue
  from (select e.src_queue_schema || '.'|| e.src_queue_name src_queue_name
             , decode(e.src_dbname, '-', null, e.src_dbname) src_dbname
             , decode(e.startup_time, b.startup_time, null, '*') a
             , e.elapsed_unpickle_time  - nvl(b.elapsed_unpickle_time,0) elapsed_unpickle_time
             , e.elapsed_rule_time      - nvl(b.elapsed_rule_time, 0)    elapsed_rule_time
             , e.elapsed_enqueue_time   - nvl(b.elapsed_enqueue_time, 0) elapsed_enqueue_time
          from stats$propagation_receiver b
             , stats$propagation_receiver e
         where b.snap_id         (+) = :bid
           and e.snap_id             = :eid
           and e.dbid                = :dbid
           and b.dbid            (+) = e.dbid
           and e.instance_number     = :inst_num
           and b.instance_number (+) = e.instance_number
           and b.src_queue_schema(+) = e.src_queue_schema
           and b.src_queue_name  (+) = e.src_queue_name
           and b.src_dbname      (+) = e.src_dbname
           and b.dst_queue_schema(+) = e.dst_queue_schema
           and b.dst_queue_name  (+) = e.dst_queue_name
           and b.startup_time    (+) = e.startup_time
         order by e.src_queue_name, e.src_dbname
       )
  where rownum <= &&streams_top_n;



set newpage 2;

ttitle lef 'Streams Apply  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
       lef '-> * indicates Apply process (re)started between Begin/End snaps' -
       skip 1 -
       lef '-> Top &&streams_top_n ordered by Apply Transactions desc' -
       skip 2;

col apply_name         format a19 trunc   heading 'Apply Name'
col a                                     heading '*'
col rate_received_txn  format        9999 heading 'Rcv|Tx/s'         just c
col rate_applied_txn   format        9999 heading 'Apply|Tx/s'       just c
col pct_wait_deps      format         999 heading 'Wait|Deps|%'      just c
col pct_wait_commits   format         999 heading 'Wait|Comit|%'     just c
col schedule_rate      format        9999 heading 'Sched|Tx/s'       just c
col reader_rate_deq    format        9999 heading 'Read|Deq|Msg/s'   just c
col reader_rate_sched  format       99999 heading 'Read|Sched|Msg/s' just c
col server_apply_rate  format        9999 heading 'Apply|Rate|Msg/s' just c
col server_pct_apply   format         999 heading 'Apply|Time|%'     just c
col server_pct_dequeue format         999 heading 'Deq|Time|%'       just c

select apply_name
     , a
     , coord_total_received/:ela                             rate_received_txn
     , coord_total_applied/:ela                              rate_applied_txn
     , decode( coord_total_applied, 0, 0
             , coord_total_wait_deps/coord_total_applied)    pct_wait_deps
     , decode( coord_total_applied, 0, 0
             , coord_total_wait_commits/coord_total_applied) pct_wait_commits
     , decode( coord_elapsed_schedule_time, 0, 0
             , coord_total_applied/coord_elapsed_schedule_time) * 100 
                                                             schedule_rate
     , reader_total_messages_dequeued/:ela                   reader_rate_deq
     , decode( reader_elapsed_schedule_time, 0, 0
             , reader_total_messages_dequeued/reader_elapsed_schedule_time) 
                                                             reader_rate_sched
     , server_total_messages_applied/:ela server_apply_rate
     ,   server_elapsed_apply_time
       / (server_elapsed_dequeue_time+server_elapsed_apply_time+1) * 100 
                                                             server_pct_apply
     ,  server_elapsed_dequeue_time
      / (server_elapsed_dequeue_time+server_elapsed_apply_time+1) * 100 
                                                             server_pct_dequeue 
  from (select e.apply_name
             , decode( e.startup_time, b.startup_time, null, '*')                          a
             , e.reader_total_messages_dequeued - nvl(b.reader_total_messages_dequeued, 0) reader_total_messages_dequeued
             , e.reader_elapsed_dequeue_time    - nvl(b.reader_elapsed_dequeue_time, 0)    reader_elapsed_dequeue_time
             , e.reader_elapsed_schedule_time   - nvl(b.reader_elapsed_schedule_time, 0)   reader_elapsed_schedule_time
             , e.coord_total_received           - nvl(b.coord_total_received, 0)           coord_total_received
             , e.coord_total_applied            - nvl(b.coord_total_applied, 0)            coord_total_applied
             , e.coord_total_wait_deps          - nvl(b.coord_total_wait_deps, 0)          coord_total_wait_deps
             , e.coord_total_wait_commits       - nvl(b.coord_total_wait_commits, 0)       coord_total_wait_commits
             , e.coord_elapsed_schedule_time    - nvl(b.coord_elapsed_schedule_time, 0)    coord_elapsed_schedule_time
             , e.server_total_messages_applied  - nvl(b.server_total_messages_applied, 0)  server_total_messages_applied
             , e.server_elapsed_dequeue_time    - nvl(b.server_elapsed_dequeue_time, 0)    server_elapsed_dequeue_time
             , e.server_elapsed_apply_time      - nvl(b.server_elapsed_apply_time, 0)      server_elapsed_apply_time
          from stats$streams_apply_sum b
             , stats$streams_apply_sum e
         where b.snap_id         (+)= :bid
           and e.snap_id            = :eid
           and e.dbid               = :dbid
           and b.dbid            (+)= e.dbid
           and e.instance_number    = :inst_num
           and b.instance_number (+)= e.instance_number
           and b.apply_name      (+)= e.apply_name
           and b.startup_time    (+)= e.startup_time
         order by e.coord_total_applied desc
       )
 where rownum <= &&streams_top_n;

set newpage 0;


ttitle lef 'Buffered Queues  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
       lef '-> * indicates Buffered Queue activity (re)started between Begin/End snaps' -
       skip 1 -
       lef '-> Top &&streams_top_n ordered by Queued Messages desc' -
       skip 2;

col qname                   format a54   trunc heading 'Queue'
col a                                          heading '*'
col enq_rate                format      99,999 heading 'Enq|Msg/s'   just c
col deq_rate                format      99,999 heading 'Deq|Msg/s'   just c
col spill_rate              format      99,999 heading 'Spill|Msg/s' just c

select queue_schema||'.'||queue_name qname
     , a
     , cnum_msgs/:ela              enq_rate
     , (cnum_msgs-num_msgs)/:ela   deq_rate
     , cspill_msgs/:ela            spill_rate
  from (select e.queue_schema
             , e.queue_name
             , decode( e.startup_time, b.startup_time, null, '*') a
             , e.num_msgs    - nvl(b.num_msgs,0)    num_msgs
             , e.cnum_msgs   - nvl(b.cnum_msgs,0)   cnum_msgs
             , e.cspill_msgs - nvl(b.cspill_msgs,0) cspill_msgs
          from stats$buffered_queues b
             , stats$buffered_queues e
         where b.snap_id         (+)= :bid
           and e.snap_id            = :eid
           and e.dbid               = :dbid
           and b.dbid            (+)= e.dbid
           and e.instance_number    = :inst_num
           and b.instance_number (+)= e.instance_number
           and b.queue_schema    (+)= e.queue_schema
           and b.queue_name      (+)= e.queue_name
           and b.startup_time    (+)= e.startup_time
         order by e.cnum_msgs desc
       )
 where rownum <= &&streams_top_n;



ttitle lef 'Buffered Queue Subscribers  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
       lef '-> * indicates Buffered Subscriber activity (re)started between Begin/End snaps' -
       skip 1 -
       lef '-> Top &&streams_top_n ordered by Queued Messages desc' -
       skip 2;

col subscriber              format a34   trunc heading 'Subscriber'
col qname                   format a25   trunc heading 'Queue'
col a                                          heading '*'
col enq_rate                format          99 heading 'Enq|Msg/s'   just c
col deq_rate                format          99 heading 'Deq|Msg/s'   just c
col spill_rate              format          99 heading 'Spill|Msg/s' just c

select decode( subscriber_type, 'PROXY', 'PROXY: '||subscriber_address
             , subscriber_name)      subscriber
     , queue_schema||'.'||queue_name  qname
     , a
     , cnum_msgs/:ela                enq_rate
     , (cnum_msgs - num_msgs)/:ela   deq_rate
     , total_spilled_msg/:ela        spill_rate
  from (select e.subscriber_name  
             , e.queue_schema
             , e.queue_name
             , decode( e.startup_time, b.startup_time, null, '*') a
             , e.subscriber_type
             , e.subscriber_address
             , e.num_msgs          - nvl(b.num_msgs,0)          num_msgs
             , e.cnum_msgs         - nvl(b.cnum_msgs,0)         cnum_msgs
             , e.total_spilled_msg - nvl(b.total_spilled_msg,0) total_spilled_msg
          from stats$buffered_subscribers b
             , stats$buffered_subscribers e
         where b.snap_id         (+)= :bid
           and e.snap_id            = :eid
           and e.dbid               = :dbid
           and b.dbid            (+)= e.dbid
           and e.instance_number    = :inst_num
           and b.instance_number (+)= e.instance_number
           and b.queue_schema    (+)= e.queue_schema
           and b.queue_name      (+)= e.queue_name
           and b.subscriber_id   (+)= e.subscriber_id
           and b.startup_time    (+)= e.startup_time
         order by e.cnum_msgs desc
       )
 where rownum <= &&streams_top_n;



ttitle lef 'Rule Sets  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
       lef '-> * indicates Rule Set activity (re)started between Begin/End snaps' -
       skip 1 -
       lef '-> Top &&streams_top_n ordered by Evaluations desc ' -
       skip 2;

col rule_name               format a35   trunc heading 'Rule'
col restart                                        heading '*'
col eval_rate               format     999,999,999 heading 'Eval/sec'
col reload_rate             format           9,999 heading 'Reloads/sec'
col pct_sql_free            format             999 heading 'No-SQL|Eval %'  just c
col pct_sql                 format             999 heading 'SQL|Eval %'     just c

select owner||'.'||name                          rule_name
     , restart
     , decode( elapsed_time, 0, 0
             , evaluations/elapsed_time * 100)   eval_rate
     , reloads/:ela                              reload_rate
     ,   sql_free_evaluations 
       / (sql_free_evaluations + sql_executions + .0000001) 
       * 100                                     pct_sql_free
     ,   sql_executions 
       / (sql_free_evaluations + sql_executions + .0000001 ) 
       * 100                                     pct_sql
  from (select e.owner
             , e.name
             , decode( e.startup_time, b.startup_time, null, '*') restart
             , e.cpu_time       - nvl(b.cpu_time,0)       cpu_time
             , e.elapsed_time   - nvl(b.elapsed_time,0)   elapsed_time
             , e.evaluations    - nvl(b.evaluations,0)    evaluations
             , e.sql_free_evaluations - nvl(b.sql_free_evaluations,0) 
                                                          sql_free_evaluations
             , e.sql_executions - nvl(b.sql_executions,0) sql_executions
             , e.reloads        - nvl(b.reloads,0)        reloads
          from stats$rule_set b
             , stats$rule_set e
          where b.snap_id         (+)= :bid
            and e.snap_id            = :eid
            and e.dbid               = :dbid
            and b.dbid            (+)= e.dbid
            and e.instance_number    = :inst_num
            and b.instance_number (+)= e.instance_number
            and b.owner           (+)= e.owner
            and b.name            (+)= e.name
            and b.startup_time    (+)= e.startup_time
          order by e.evaluations desc
       )
 where rownum <= &&streams_top_n;



--
--  Streams Pool Advisory

ttitle lef 'Streams Pool Advisory  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'End Snap: ' format 99999999 end_snap -
       skip 2;

column spsfe    format      9,999,999.9  heading 'Streams Pool|Size (M)';
column spsf     format             99.0  heading 'Streams Pool|Size Factor';
column esc      format        999,990    heading 'Est Spill|Count';
column est      format        999,990    heading 'Est Spill|Time (s)';
column eusc     format        999,990    heading 'Est Unspill|Count';
column eust     format        999,990    heading 'Est Unspill|Time (s)';

select streams_pool_size_for_estimate/&&btomb spsfe
     , streams_pool_size_factor       spsf
     , estd_spill_count               esc
     , estd_spill_time                est
     , estd_unspill_count             eusc
     , estd_unspill_time              eust
  from stats$streams_pool_advice
 where snap_id             = :eid
   and dbid                = :dbid
   and instance_number     = :inst_num
 order by streams_pool_size_for_estimate;



--  Shared Pool Advisory

ttitle lef 'Shared Pool Advisory  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'End Snap: ' format 99999999 end_snap -
       skip 1 -
       lef '-> SP: Shared Pool     Est LC: Estimated Library Cache   Factr: Factor' -
       skip 1 -
       lef '-> Note there is often a 1:Many correlation between a single logical object' -
       skip 1 -
       lef '   in the Library Cache, and the physical number of memory objects associated' -
       skip 1 - 
       lef '   with it.  Therefore comparing the number of Lib Cache objects (e.g. in ' -
       skip 1 -
       lef '   v$librarycache), with the number of Lib Cache Memory Objects is invalid' - 
       skip 2;

column spsfe  format      9,999,999    heading 'Shared|Pool|Size (M)';
column spsf   format             99.0  heading 'SP|Size|Factr';
column elcs   format        999,990    heading 'Est LC|Size|(M)';
column elcmo  format    999,999,999    heading 'Est LC|Mem Obj';
column elcts  format         99,999    heading 'Est LC|Time|Saved|(s)';
column elctsf format             99.0  heading 'Est LC|Time|Saved|Factr';
column elclt  format         99,999    heading 'Est LC|Load|Time|(s)';
column elcltf format             99.0  heading 'Est LC|Load|Time|Factr';
column elcmoh format     99,999,999    heading 'Est LC|Mem|Obj Hits';

select shared_pool_size_for_estimate spsfe
     , shared_pool_size_factor       spsf
     , estd_lc_size                  elcs
     , estd_lc_memory_objects        elcmo
     , estd_lc_time_saved            elcts
     , estd_lc_time_saved_factor     elctsf
     , estd_lc_load_time             elclt
     , estd_lc_load_time_factor      elcltf
     , estd_lc_memory_object_hits    elcmoh
  from stats$shared_pool_advice
 where snap_id             = :eid
   and dbid                = :dbid
   and instance_number     = :inst_num
 order by shared_pool_size_for_estimate;



--
-- Java Pool Advisory

set newpage 2;

ttitle lef 'Java Pool Advisory  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'End Snap: ' format 99999999 end_snap -
       skip 2;

column jpsfe  format      9,999,999    heading 'Java|Pool|Size(M)';
column jpsf   format             99.0  heading 'JP|Size|Factr';
column elcs   format        999,990    heading 'Est LC|Size|(M)';
column elcmo  format    999,999,999    heading 'Est LC|Mem Obj';
column elcts  format         99,999    heading 'Est LC|Time|Saved|(s)';
column elctsf format             99.0  heading 'Est LC|Time|Saved|Factr';
column elclt  format         99,999    heading 'Est LC|Load|Time|(s)';
column elcltf format             99.0  heading 'Est LC|Load|Time|Factr';
column elcmoh format     99,999,999    heading 'Est LC|Mem|Obj Hits';

select java_pool_size_for_estimate   jpsfe
     , java_pool_size_factor         jpsf
     , estd_lc_size                  elcs
     , estd_lc_memory_objects        elcmo
     , estd_lc_time_saved            elcts
     , estd_lc_time_saved_factor     elctsf
     , estd_lc_load_time             elclt
     , estd_lc_load_time_factor      elcltf
     , estd_lc_memory_object_hits    elcmoh
  from stats$java_pool_advice
 where snap_id             = :eid
   and dbid                = :dbid
   and instance_number     = :inst_num
   and estd_lc_memory_objects > 0
 order by java_pool_size_for_estimate;


--
-- SGA cache size changes

ttitle lef 'Cache Size Changes  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
       lef '-> Not all cache size changes may be captured.  Only cache changes which are' -
       skip 1 -
       lef '   evident at snapshot time are shown' -
       skip 2;

column cache       format a12     heading 'Cache'
column prev_value  format 999,999 heading 'Prior|Size (MB)' just c
column value       format 999,999 heading 'New|Size (MB)'   just c
colum  diff        format 999,999 heading 'Difference|(MB)' just c

break on snap_id
select snap_id
     , decode(name, '__db_cache_size',     'Buffer Cache'
                  , '__shared_pool_size',  'Shared Pool'
                  , '__large_pool_size',   'Large Pool'
                  , '__java_pool_size',    'Java Pool'
                  , '__streams_pool_size', 'Streams Pool') cache
     , prev_value
     , value
     , (value - prev_value) diff
  from (select snap_id, name
             , to_number(value)/&btomb value
             , to_number((lag(value, 1, null) over (order by name, snap_id)))/&btomb prev_value
             , (lag(name, 1, null)  over (order by name, snap_id)) prev_name
          from stats$parameter
         where snap_id   between :bid and :eid
           and dbid            = :dbid
           and instance_number = :inst_num
           and name in ('__shared_pool_size', '__db_cache_size'
                       ,'__large_pool_size' , '__java_pool_size'
                       ,'__streams_pool_size')
       )
 where value != prev_value
   and name   = prev_name
 order by snap_id, diff;
clear breaks



set newpage 0;

ttitle lef 'SGA Target Advisory  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'End Snap: ' format 99999999 end_snap -
       skip 2;

column sgatsfe  format      9,999,999    heading 'SGA Target|Size (M)';
column sgasf    format             99.0  heading 'SGA Size|Factor';
column edbts    format        999,990    heading 'Est DB|Time (s)';
column edbtf    format             99.0  heading 'Est DB|Time Factor';
column epr      format  9,999,999,999    heading 'Est Physical|Reads';

select sga_size            sgatsfe
     , sga_size_factor     sgasf
     , estd_db_time        edbts
     , estd_db_time_factor edbtf
     , estd_physical_reads epr
  from stats$sga_target_advice
 where snap_id             = :eid
   and dbid                = :dbid
   and instance_number     = :inst_num
 order by sga_size;


--
--  SGA

column name    format a30                 heading 'SGA regions';
column bval    format 999,999,999,999,990 heading 'Begin Size (Bytes)';
column eval    format 999,999,999,999,990 heading 'End Size (Bytes)|(if different)';

break on report;
compute sum of bval on report;
compute sum of eval on report;
ttitle lef 'SGA Memory Summary  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 2;

select e.name
     , b.value                                            bval
     , decode(b.value, e.value, to_number(null), e.value) eval
  from stats$sga b
     , stats$sga e
 where e.snap_id         = :eid
   and e.dbid            = :dbid
   and e.instance_number = :inst_num
   and b.snap_id         = :bid
   and b.dbid            = :dbid
   and b.instance_number = :inst_num
   and b.name            = e.name
 order by name;
clear break compute;


set newpage 2;

ttitle lef 'SGA breakdown difference  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 1 -
       lef '-> Top &sgastat_top_n rows by size, ordered by Pool, Name (note rows with null values for' -
       skip 1 -
       lef '   Pool column, or Names showing free memory are always shown)' -
       skip 1 -
       lef '-> Null value for Begin MB or End MB indicates the size of that Pool/Name was' -
       skip 1 - 
       lef '   insignificant, or zero in that snapshot' -
       skip 2;

column pool  format a6                 heading 'Pool' trunc ;
column name  format a30                heading 'Name';
column snap1 format 999,999,999.9      heading 'Begin MB';
column snap2 format 999,999,999.9      heading 'End MB';
column diff  format            9990.90 heading '% Diff';

-- inline views in from clause required to prevent full outer join
-- from applying where clause after outer join.  ANSI SQL standard
-- described in (bug 3805503)

select *
  from (select nvl(e.pool, b.pool)             pool
             , nvl(e.name, b.name)             name
             , b.bytes/1024/1024               snap1
             , e.bytes/1024/1024               snap2
             , 100*(nvl(e.bytes,0) - nvl(b.bytes,0))/nvl(b.bytes,1) diff
          from (select *
                  from stats$sgastat 
                 where snap_id         = :bid
                   and dbid            = :dbid
                   and instance_number = :inst_num
               ) b 
               full outer join
               (select *
                  from stats$sgastat 
                 where snap_id         = :eid
                   and dbid            = :dbid
                   and instance_number = :inst_num
               ) e
               on b.name             = e.name
               and nvl(b.pool, 'a')  = nvl(e.pool, 'a')
          order by nvl(e.bytes, b.bytes)
       )
 where pool   is null
    or name    = 'free memory'
    or rownum <= &&sgastat_top_n
order by pool, name;

set newpage 0;



--
--  SQL Memory stats

set heading off;

ttitle lef 'SQL Memory Statistics  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 2;

select '                                   Begin            End         % Diff'            ch78n
     , '                          -------------- -------------- --------------'            ch78n
     , '   Avg Cursor Size (KB): ' ch25n, :b_total_sql_mem/&&btokb/:b_total_cursors        num8c_2
                                        , :e_total_sql_mem/&&btokb/:e_total_cursors        num8c_2
                                        , 100*(  (:e_total_sql_mem/&&btokb/:e_total_cursors)
                                               - (:b_total_sql_mem/&&btokb/:b_total_cursors)
                                              )
                                             /(:e_total_sql_mem/&&btokb/:e_total_cursors)   num8c_2
     , ' Cursor to Parent ratio: ' ch25n, :b_total_cursors/:b_total_sql                     num8c_2
                                        , :e_total_cursors/:e_total_sql                     num8c_2
                                        , 100*( (:e_total_cursors/:e_total_sql)
                                               -(:b_total_cursors/:b_total_sql)
                                              )
                                             /(:e_total_cursors/:e_total_sql)               num8c_2
     , '          Total Cursors: ' ch25n, :b_total_cursors                                  num10c
                                        , :e_total_cursors                                  num10c
                                        , 100*( (:e_total_cursors)
                                               -(:b_total_cursors)
                                              )
                                             /(:e_total_cursors)                            num8c_2
     , '          Total Parents: ' ch25n, :b_total_sql                                      num10c
                                        , :e_total_sql                                      num10c
                                        , 100*( (:e_total_sql)
                                               -(:b_total_sql)
                                              )
                                             /(:e_total_sql)                                num8c_2
  from sys.dual
 where :b_total_cursors > 0
   and :e_total_cursors > 0;

set heading on;


--
--  Resource Limit

set newpage 2;

ttitle lef 'Resource Limit Stats  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'End Snap: ' format 99999999 end_snap -
       skip 1 -
       lef '-> only rows with Current or Maximum Utilization > 80% of Limit are shown' -
       skip 1 -
       lef '-> ordered by resource name' -
       skip 2;

column rname    format a30              heading 'Resource Name';
column curu     format 999,999,990      heading 'Current|Utilization' just c;
column maxu     format 999,999,990      heading 'Maximum|Utilization' just c;
column inita    format a10              heading 'Initial|Allocation'  just c;
column lim      format a10              heading 'Limit'               just r;

select resource_name         rname
     , current_utilization   curu
     , max_utilization       maxu
     , initial_allocation    inita
     , limit_value           lim
  from stats$resource_limit
 where snap_id         = :eid
   and dbid            = :dbid
   and instance_number = :inst_num
   and (   nvl(current_utilization,0)/limit_value > .8
        or nvl(max_utilization,0)/limit_value     > .8
       )
 order by rname;

set newpage 0;


--
--  Initialization Parameters

column name     format a29      heading 'Parameter Name'         trunc;
column bval     format a33      heading 'Begin value'            trunc;
column eval     format a14      heading 'End value|(if different)' trunc just c;
 
ttitle lef 'init.ora Parameters  '-
           'DB/Inst: ' db_name '/' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap '-' format 99999999 end_snap -
       skip 2;

select e.name
     , b.value                                bval
     , decode(b.value, e.value, ' ', e.value) eval
  from stats$parameter b
     , stats$parameter e
 where b.snap_id(+)         = :bid
   and e.snap_id            = :eid
   and b.dbid(+)            = :dbid
   and e.dbid               = :dbid
   and b.instance_number(+) = :inst_num
   and e.instance_number    = :inst_num
   and b.name(+)            = e.name
   and translate(e.name, '_', '#') not like '##%'
   and (   nvl(b.isdefault, 'X')   = 'FALSE'
        or nvl(b.ismodified,'X')  != 'FALSE'
        or     e.ismodified       != 'FALSE'
        or nvl(e.value,0)         != nvl(b.value,0)
       )
 order by e.name;

prompt
prompt End of Report ( &report_name )
prompt
spool off;
set termout off;
clear columns sql;
ttitle off;
btitle off;
repfooter off;
set linesize 78 termout on feedback 6;
undefine begin_snap
undefine end_snap
undefine dbid
undefine inst_num
undefine num_days
undefine report_name
undefine top_n_sql
undefine top_pct_sql
undefine top_n_events
undefine top_n_segstat
undefine btime
undefine etime
undefine num_rows_per_hash
whenever sqlerror continue;

--
--  End of script file;
