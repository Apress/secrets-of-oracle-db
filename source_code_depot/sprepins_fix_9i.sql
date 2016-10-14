Rem
Rem $Header: sprepins.sql 17-may-2004.14:15:50 cdialeri Exp $
Rem
Rem sprepins.sql
Rem
Rem Copyright (c) 2001, 2004, Oracle. All rights reserved.  
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
Rem    cdialeri    05/11/04 - 3566569
Rem    vbarrier    03/21/03 - 2726042
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

clear break compute;
repfooter off;
ttitle off;
btitle off;
set timing off veri off space 1 flush on pause off termout on numwidth 10;
set echo off feedback off pagesize 60 linesize 80 newpage 1 recsep off;
set trimspool on trimout on;
define top_n_events = 5;
define top_n_sql = 65;
define top_n_segstat = 5;
define num_rows_per_hash=5;


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
--  Ask for the snapshots Id's which are to be compared

set termout on;
column instart_fmt noprint;
column inst_name   format a12  heading 'Instance';
column db_name     format a12  heading 'DB Name';
column snap_id     format 99999990 heading 'Snap|Id';
column snapdat     format a17  heading 'Snap Started' just c;
column lvl         format 99   heading 'Snap|Level';
column commnt      format a20  heading 'Comment';

break on inst_name on db_name on host on instart_fmt skip 1;

ttitle lef 'Completed Snapshots' skip 2;

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
 order by db_name, instance_name, snap_id;

clear break;
ttitle off;


prompt
prompt
prompt Specify the Begin and End Snapshot Ids
prompt ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
prompt Begin Snapshot Id specified: &&begin_snap
prompt
prompt End   Snapshot Id specified: &&end_snap
prompt


--
--  Set up the snapshot-related binds, and additional instance info

set termout off;

variable bid        number;
variable eid        number;
begin
  :bid       :=  &&begin_snap;
  :eid       :=  &&end_snap;
end;
/

column para       new_value para;
column versn      new_value versn;
column host_name  new_value host_name;
column db_name    new_value db_name;
column inst_name  new_value inst_name;
column btime      new_value btime;
column etime      new_value etime;

select parallel       para
     , version        versn
     , host_name      host_name
     , db_name        db_name
     , instance_name  inst_name
     , to_char(snap_time, 'YYYYMMDD HH24:MI:SS')  btime
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
begin
  :para      := '&para';
  :versn     := '&versn';
  :host_name := '&host_name';
  :db_name   := '&db_name';
  :inst_name := '&inst_name';
  :btime     := '&btime';
  :etime     := '&etime';
end;
/

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

set heading off;
column report_name new_value report_name noprint;
select 'Using the report name ' || nvl('&&report_name','&dflt_name')
     , nvl('&&report_name','&dflt_name') report_name
  from sys.dual;
spool &report_name;
set heading on;
prompt


--
--  Verify begin and end snapshot Ids exist for the database, and that
--  there wasn't an instance shutdown in between the two snapshots 
--  being taken.

set heading off;
select 'ERROR: Database/Instance does not exist in STATS$DATABASE_INSTANCE'
  from dual
 where not exists
      (select null
         from stats$database_instance
        where instance_number = :inst_num
          and dbid            = :dbid);


select 'ERROR: Begin Snapshot Id specified does not exist for this database/instance'
  from dual
 where not exists
      (select null
         from stats$snapshot b
        where b.snap_id         = :bid
          and b.dbid            = :dbid
          and b.instance_number = :inst_num);


select 'ERROR: End Snapshot Id specified does not exist for this database/instance'
  from dual
 where not exists
      (select null
         from stats$snapshot e
        where e.snap_id         = :eid
          and e.dbid            = :dbid
          and e.instance_number = :inst_num);


select 'WARNING: timed_statitics setting changed between begin/end snaps: TIMINGS ARE INVALID'
  from dual
 where not exists
      (select null
         from stats$parameter b
            , stats$parameter e
        where b.snap_id         = :bid
          and e.snap_id         = :eid
          and b.dbid            = :dbid
          and e.dbid            = :dbid
          and b.instance_number = :inst_num
          and e.instance_number = :inst_num
          and b.name            = e.name
          and b.name            = 'timed_statistics'
          and b.value           = e.value);


select 'ERROR: Snapshots chosen span an instance shutdown: RESULTS ARE INVALID'
  from dual
 where not exists
      (select null
         from stats$snapshot b
            , stats$snapshot e
        where b.snap_id         = :bid
          and e.snap_id         = :eid
          and b.dbid            = :dbid
          and e.dbid            = :dbid
          and b.instance_number = :inst_num
          and e.instance_number = :inst_num
          and b.startup_time    = e.startup_time);

select 'ERROR: Session statistics are for different sessions: RESULTS NOT PRINTED'
  from dual
 where not exists
      (select null
         from stats$snapshot b
            , stats$snapshot e
        where b.snap_id         = :bid
          and e.snap_id         = :eid
          and b.dbid            = :dbid
          and e.dbid            = :dbid
          and b.instance_number = :inst_num
          and e.instance_number = :inst_num
          and b.session_id      = e.session_id
          and b.serial#         = e.serial#);

set heading on;


--
--

set newpage 1 heading on;


--
--  Call statspack to calculate certain statistics
--

set heading off;
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
variable phyw   number;
variable prse   number;
variable hprs   number;
variable recr   number;
variable gets   number;
variable rlsr   number;
variable rent   number;
variable srtm   number;
variable srtd   number;
variable srtr   number;
variable strn   number;
variable call   number;
variable lhr    number;
variable sp     varchar2(512);
variable bc     varchar2(512);
variable lb     varchar2(512);
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
variable glsc   number;
variable glac   number;
variable glct   number;
variable glrl   number;
variable gcdfr  number;
variable gcge   number;
variable gcgt   number;
variable gccv   number;
variable gcct   number;
variable gccrrv   number;
variable gccrrt   number;
variable gccurv   number;
variable gccurt   number;
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
   , :para                 -- End of IN arguments
   , :lhtr,   :bfwt
   , :tran,   :chng
   , :ucal,   :urol
   , :rsiz
   , :phyr,   :phyrd
   , :phyrdl
   , :phyw,   :ucom
   , :prse,   :hprs
   , :recr,   :gets
   , :rlsr,   :rent
   , :srtm,   :srtd
   , :srtr,   :strn
   , :lhr,    :bc
   , :sp,     :lb
   , :bs,     :twt
   , :logc,   :prscpu
   , :tcpu,   :exe
   , :prsela
   , :bspm,   :espm
   , :bfrm, :efrm
   , :blog,   :elog
   , :bocur,  :eocur
   , :dmsd,   :dmfc    -- Begin of RAC
   , :dmsi
   , :pmrv,   :pmpt 
   , :npmrv,  :npmpt 
   , :dbfr
   , :dpms,   :dnpms 
   , :glsg,   :glag 
   , :glgt,   :glsc 
   , :glac,   :glct 
   , :glrl,   :gcdfr
   , :gcge,   :gcgt 
   , :gccv,   :gcct
   , :gccrrv, :gccrrt 
   , :gccurv, :gccurt 
   , :gccrsv
   , :gccrbt, :gccrft 
   , :gccrst, :gccusv 
   , :gccupt, :gccuft 
   , :gccust
   , :msgsq,  :msgsqt
   , :msgsqk, :msgsqtk
   , :msgrq,  :msgrqt           -- End RAC
   );
   :call := :ucal + :recr;
end;
/

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
column dbid      heading "DB Id"     new_value dbid      format 9999999999 just c;
column host_name heading "Host"     format a12 print;
column para      heading "Cluster"  format a7  print;
column versn     heading "Release"  format a11  print;

select :db_name    db_name
     , :dbid       dbid
     , :inst_name  inst_name
     , :inst_num   inst_num
     , :versn      versn
     , :para       para
     , :host_name  host_name
  from sys.dual;


--
--  Print snapshot information

column inst_num   noprint
column instart_fmt new_value INSTART_FMT noprint;
column instart    new_value instart noprint;
column session_id new_value SESSION noprint;
column ela        new_value ELA     noprint;
column btim       new_value btim    heading 'Start Time' format a19 just c;
column etim       new_value etim    heading 'End Time'   format a19 just c;
column xbid        format 99999990;
column xeid        format 99999990;
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
select '              Snap Id     Snap Time      Sessions Curs/Sess Comment' nl
     , '            --------- ------------------ -------- --------- -------------------'    nl
     , 'Begin Snap:'                                          nl11
     , b.snap_id                                                xbid
     , to_char(b.snap_time, 'dd-Mon-yy hh24:mi:ss')             btim
     , :blog                                                    blog
     , :bocur/:blog                                             ocs
     , b.ucomment                                               comm
     , '  End Snap:'                                          nl11
     , e.snap_id                                                xeid
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
     , b.seg_phy_reads_th					bspr
     , e.seg_phy_reads_th					espr
     , b.seg_log_reads_th					bslr
     , e.seg_log_reads_th					eslr
     , b.seg_buff_busy_th					bsbb
     , e.seg_buff_busy_th					esbb
     , b.seg_rowlock_w_th					bsrl
     , e.seg_rowlock_w_th					esrl
     , b.seg_itl_waits_th					bsiw
     , e.seg_itl_waits_th					esiw
     , b.seg_cr_bks_sd_th                                       bcrb
     , e.seg_cr_bks_sd_th                                       ecrb
     , b.seg_cu_bks_sd_th                                       bcub
     , e.seg_cu_bks_sd_th                                       ecub
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
end;
/

--
--

set heading off;

--
--  Cache Sizes

column dscr  format a28 newline;
column dscr2 format a21;
column val  format a10 just r;

select 'Cache Sizes (end)'                                          dscr
     , '~~~~~~~~~~~~~~~~~'                                          dscr
     , '               Buffer Cache:'                               dscr
     , lpad(to_char(round(:bc/1024/1024),'999,999') || 'M', 10)     val
     , '     Std Block Size:'                                       dscr2
     , lpad(to_char((:bs/1024)          ,'999') || 'K',10)          val
     , '           Shared Pool Size:'                               dscr
     , lpad(to_char(round(:sp/1024/1024),'999,999') || 'M',10)      val
     , '         Log Buffer:'                                       dscr2
     , lpad(to_char(round(:lb/1024)     ,'999,999') || 'K', 10)     val
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
column lhead    format a21;

select 'Load Profile'
      ,'~~~~~~~~~~~~                            Per Second       Per Transaction'
      ,'                                   ---------------       ---------------'
      ,'                  Redo size:' dscr, round(:rsiz/:ela,2)  val
                                          , round(:rsiz/:tran,2) val
      ,'              Logical reads:' dscr, round(:gets/:ela,2)  val
                                          , round(:gets/:tran,2) val
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
      ,'  % Blocks changed per Read:' dscr, round(100*:chng/:gets,2) pctval
      ,'   Recursive Call %:'         lhead, round(100*:recr/:call,2) bpctval
      ,' Rollback per transaction %:' dscr, round(100*:urol/:tran,2) pctval
      ,'      Rows per Sort:'         lhead, decode((:srtm+:srtd)
						   ,0,to_number(null)
                                            ,round(:srtr/(:srtm+:srtd),2)) bpctval
 from sys.dual;


--
--  Instance Efficiency Percentages

column ldscr  format a50
column lhead  format a22;

column nl format a60 newline;
select 'Instance Efficiency Percentages (Target 100%)' ldscr
      ,'~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~' ldscr
      ,'            Buffer Nowait %:'                  dscr
      , round(100*(1-:bfwt/:gets),2)                   pctval
      ,'      Redo NoWait %:'                          lhead
      , decode(:rent,0,to_number(null), round(100*(1-:rlsr/:rent),2))  pctval
      ,'            Buffer  Hit   %:'                  dscr
      , round(100*(1-(:phyr-:phyrd-nvl(:phyrdl,0))/:gets),2)           pctval
      ,'   In-memory Sort %:'                          lhead
      , decode((:srtm+:srtd),0,to_number(null),
                               round(100*:srtm/(:srtd+:srtm),2))       pctval
      ,'            Library Hit   %:'                  dscr
      , round(100*:lhtr,2)                             pctval
      ,'       Soft Parse %:'                          lhead
      , round(100*(1-:hprs/:prse),2)                   pctval
      ,'         Execute to Parse %:'                  dscr
      , round(100*(1-:prse/:exe),2)                    pctval
      ,'        Latch Hit %:'                          lhead
      , round(100*(1-:lhr),2)                          pctval
      ,'Parse CPU to Parse Elapsd %:'                  dscr
      , decode(:prsela, 0, to_number(null)
                      , round(100*:prscpu/:prsela,2))  pctval
      ,'    % Non-Parse CPU:'                          lhead
      , decode(:tcpu, 0, to_number(null)
                    , round(100*(1-(:prscpu/:tcpu)),2))  pctval
  from sys.dual;

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
  from stats$sql_statistics b
     , stats$sql_statistics e
 where b.snap_id         = :bid
   and e.snap_id         = :eid
   and b.instance_number = :inst_num
   and e.instance_number = :inst_num
   and b.dbid            = :dbid
   and e.dbid            = :dbid;


--
--

set heading on;
repfooter center -
   '-------------------------------------------------------------';

--
--  Top Wait Events

col idle     noprint;
col event    format a44          heading 'Top 5 Timed Events|~~~~~~~~~~~~~~~~~~|Event';
col waits    format 999,999,990  heading 'Waits';
col time     format 99,999,990   heading 'Time (s)';
col pctwtt   format 999.99       heading '% Total|Ela Time';

select event
     , waits
     , time
     , pctwtt
  from (select event, waits, time, pctwtt
          from (select e.event                               event
                     , e.total_waits - nvl(b.total_waits,0)  waits
                     , (e.time_waited_micro - nvl(b.time_waited_micro,0))/1000000  time
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

set space 1 termout on newpage 0;
whenever sqlerror exit;


--
-- Beginning of Cluster specific Ratios

set heading off;

column hd       format a51 newline;
column pct      format 9999990.0;
column avg_time format 999,990.0;
column rat      format 999,990.0;

select    'Cluster Statistics for DB: ' || :db_name || '  ' || 'Instance: ' || :inst_name
       || '  ' || 'Snaps: ' || :bid || ' -' || :eid header
     , ' ' nl
     , 'Global Cache Service - Workload Characteristics' nl
     , '-----------------------------------------------' nl
     , 'Ave global cache get time (ms): '                              hd
     , decode (:gcge, 0, to_number(NULL)
                       , 10 * (:gcgt / :gcge))                         avg_time
     , 'Ave global cache convert time (ms):'                           hd
     , decode(:gccv, 0, to_number(NULL)
                   , 10 * (:gcct / :gccv))                             avg_time
     , ' ' nl
     , 'Ave build time for CR block (ms): '                            hd
     , decode(:gccrsv, 0, to_number(NULL)
                     , 10 * :gccrbt / :gccrsv)                         avg_time
     , 'Ave flush time for CR block (ms): '                            hd
     , decode(:gccrsv, 0, to_number(NULL)
                     , 10 * :gccrft / :gccrsv)                         avg_time
     , 'Ave send time for CR block (ms): '                             hd
     , decode(:gccrsv, 0, to_number(NULL)
                     , 10 * :gccrst / :gccrsv)                         avg_time
     , 'Ave time to process CR block request (ms): '                   hd
     , decode(:gccrsv, 0, to_number(NULL)
                     , ((:gccrbt + :gccrft + :gccrst) / :gccrsv) * 10) avg_time
     , 'Ave receive time for CR block (ms): '                          hd
     , decode(:gccrrv, 0, to_number(NULL)
                     , 10 * :gccrrt / :gccrrv)                         avg_time
     , ' ' nl
     , 'Ave pin time for current block (ms):'                          hd
     , decode(:gccusv, 0, to_number(NULL)
                     , 10 * :gccupt / :gccusv)                         avg_time
     , 'Ave flush time for current block (ms):'                        hd
     , decode(:gccusv, 0, to_number(NULL)
                     , 10 * :gccuft / :gccusv)                         avg_time
     , 'Ave send time for current block (ms):'                         hd
     , decode(:gccusv, 0, to_number(NULL)
                     , 10 * :gccust / :gccusv)                         avg_time
     , 'Ave time to process current block request (ms): '              hd 
     , decode(:gccusv, 0, to_number(NULL) 
            , ((:gccupt + :gccuft + :gccust) / :gccusv) * 10)          avg_time
     , 'Ave receive time for current block (ms):'                      hd
     , decode(:gccurv, 0, to_number(NULL)
                     , 10 * :gccurt / :gccurv)                         avg_time
     , ' ' nl
     , 'Global cache hit ratio:'                                       hd
     , decode(:gets, 0, to_number(NULL)
                   , 100 * (:gcge + :gccv + :gccrrv + :gccurv) / :gets) pct
     , 'Ratio of current block defers:'                                hd
     , decode(:gccusv, 0, to_number(NULL)
                     , :gcdfr / :gccusv)                               pct
     , '% of messages sent for buffer gets: '                          hd
     , decode(:gets, 0, to_number(NULL)
                   , 100 * (:dpms / :gets))                            pct
     , '% of remote buffer gets: '                                     hd
     , decode(:gets, 0, to_number(NULL)
                   , 100 * ((:gccurv+:gccrrv) / :gets))                pct
     , 'Ratio of I/O for coherence:'                                   hd
     , decode(:phyr, 0, to_number(NULL)
                   , (:gcge / :phyr))                                  pct
     , 'Ratio of local vs remote work:'                                hd
     , decode(:gccrrv+:gccurv, 0, to_number(NULL)
                   , ((:gcge + :gccv) / (:gccrrv + :gccurv)))          pct
     , 'Ratio of fusion vs physical writes:'                           hd
     , decode(:phyw, 0, to_number(NULL)
                   , ((:dbfr) / (:phyw)))                              pct
     , ' ' nl
     , 'Global Enqueue Service Statistics' nl
     , '---------------------------------' nl
     , 'Ave global lock get time (ms): '                               hd
     , decode(:glag+:glsg, 0, to_number(NULL)
                         , (:glgt / (:glag+:glsg)) * 10)               avg_time
     , 'Ave global lock convert time (ms): '                           hd
     , decode(:glac+:glsc, 0, to_number(NULL)
                        , (:glct / (:glac+:glsc)) * 10)                avg_time
     , 'Ratio of global lock gets vs global lock releases: '           hd
     , decode(:glrl, 0, to_number(NULL)
                      , (:glsg+:glag)/:glrl)                           pct
     , ' ' nl
     , 'GCS and GES Messaging statistics' nl
     , '--------------------------------' nl
     , 'Ave message sent queue time (ms): '                            hd
     , decode(:msgsq, 0, to_number(NULL), :msgsqt / :msgsq)            avg_time
     , 'Ave message sent queue time on ksxp (ms): '                    hd
     , decode(:msgsqk, 0, to_number(NULL), :msgsqtk / :msgsqk)         avg_time
     , 'Ave message received queue time (ms): '                        hd
     , decode(:msgrq, 0, to_number(NULL), :msgrqt / :msgrq)            avg_time
     , 'Ave GCS message process time (ms): '                           hd
     , decode(:pmrv, 0, to_number(NULL), :pmpt / :pmrv)                avg_time
     , 'Ave GES message process time (ms): '                           hd
     , decode(:npmrv, 0, to_number(NULL), :npmpt / :npmrv)             avg_time
     , '% of direct sent messages: '                                   hd
     , decode((:dmsd + :dmsi + :dmfc), 0 , to_number(NULL)
                           , (100 * :dmsd) / (:dmsd + :dmsi + :dmfc))  pct
     , '% of indirect sent messages: '                                 hd
     , decode((:dmsd + :dmsi + :dmfc), 0, to_number(NULL)
                           , (100 * :dmsi) / (:dmsd + :dmsi + :dmfc))  pct
     , '% of flow controlled messages: '                               hd
     , decode((:dmsd+:dmsi+:dmfc), 0, to_number(NULL)
                                    , 100 * :dmfc / (:dmsd+:dmsi+:dmfc)) pct
  from sys.dual
 where :para = 'YES';

set heading on newpage 0;


--
--  Miscellaneous GES Cluster Statistics 

ttitle lef 'GES Statistics for ' -
           'DB: ' db_name  '  Instance: ' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap ' -' format 99999999 end_snap -
       skip 2;

column st	format a33              heading 'Statistic' trunc;
column dif	format 999,999,999,990	heading 'Total';
column ps	format 9,999,990.9	heading 'per Second';
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


--  End of Cluster specific statistics
--


--
--  System Events

ttitle lef 'Wait Events for ' -
           'DB: ' db_name  '  Instance: ' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap ' -' format 99999999 end_snap -
       skip 1 -
           '-> s  - second      ' -
       skip 1 -
           '-> cs - centisecond -     100th of a second' -
       skip 1 -
           '-> ms - millisecond -    1000th of a second' -
       skip 1 -
           '-> us - microsecond - 1000000th of a second' -
       skip 1 -
       lef '-> ordered by wait time desc, waits desc (idle events last)' -
       skip 2;

col idle noprint;
col event    format a28         heading 'Event' trunc;
col waits    format 999,999,990 heading 'Waits';
col timeouts format 9,999,990   heading 'Timeouts';
col time     format 9,999,990   heading 'Total Wait|Time (s)';
col wt       format 99990       heading 'Avg|wait|(ms)';
col txwaits  format 9,990.0     heading 'Waits|/txn';

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
   and e.total_waits         > nvl(b.total_waits,0)
   and e.event       not in ('smon timer','pmon timer','dispatcher timer','dispatcher listen timer')
   and e.event       not like 'rdbms ipc%'
   and i.event(+)            = e.event
 order by idle, time desc, waits desc;



--
--  Background process wait events

ttitle lef 'Background Wait Events for ' -
           'DB: ' db_name  '  Instance: ' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap ' -' format 99999999 end_snap -
       skip 1 -
       lef '-> ordered by wait time desc, waits desc (idle events last)' -
       skip 2;

break on idle;
select e.event
     , e.total_waits - nvl(b.total_waits,0)                waits
     , e.total_timeouts - nvl(b.total_timeouts,0)          timeouts
     , (e.time_waited_micro - nvl(b.time_waited_micro,0))/1000000                time
     , decode ((e.total_waits - nvl(b.total_waits, 0)),
               0, to_number(NULL),
                  ((e.time_waited_micro - nvl(b.time_waited_micro,0))/1000)
                 / (e.total_waits - nvl(b.total_waits,0)) )        wt
     , (e.total_waits - nvl(b.total_waits,0))/:tran        txwaits
     , decode(i.event, null, 0, 99)                        idle
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
   and i.event(+)           = e.event
 order by idle, time desc, waits desc;
clear break;


--
--  SQL Reporting

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
--  SQL statements ordered by buffer gets

ttitle lef 'SQL ordered by Gets for ' -
           'DB: ' db_name  '  Instance: ' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap ' -' format 99999999 end_snap -
       skip 1 -
           '-> End Buffer Gets Threshold: '   ebgt -
       skip 1 -
           '-> Note that resources reported for PL/SQL includes the ' -
           'resources used by' skip 1 -
           '   all SQL statements called within the PL/SQL code.  As ' -
           'individual SQL'    skip 1 -
           '   statements are also reported, it is possible and valid ' -
           'for the summed'    skip 1 -
           '   total % to exceed 100' -
       skip 2;

-- Bug 1313544 requires this rather bizarre SQL statement

set underline off;
col aa format a80 heading -
'                                                     CPU      Elapsd|  Buffer Gets    Executions  Gets per Exec  %Total Time (s)  Time (s) Hash Value |--------------- ------------ -------------- ------ -------- --------- ----------' 

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
                  lpad((to_char(100*(e.buffer_gets - nvl(b.buffer_gets,0))/:gets
                               ,'990.0'))
                      , 6) ||' '||
                  lpad(  nvl(to_char(  (e.cpu_time - nvl(b.cpu_time,0))/1000000
                                   , '9990.00')
                       , ' '),8) || ' ' ||
                  lpad(  nvl(to_char(  (e.elapsed_time - nvl(b.elapsed_time,0))/1000000
                                   , '99990.00')
                       , ' '),9) || ' ' ||
                  lpad(e.hash_value,10)||''||
                  decode(e.module,null,st.sql_text
                                      ,rpad('Module: '||e.module,80)||st.sql_text)
                , st.sql_text) aa
          , e.hash_value hv
       from stats$sql_summary e
          , stats$sql_summary b
          , stats$sqltext     st 
      where b.snap_id(+)         = :bid
        and b.dbid(+)            = e.dbid
        and b.instance_number(+) = e.instance_number
        and b.hash_value(+)      = e.hash_value
        and b.address(+)         = e.address
        and b.text_subset(+)     = e.text_subset
        and e.snap_id            = :eid
        and e.dbid               = :dbid
        and e.instance_number    = :inst_num
        and e.hash_value         = st.hash_value 
        and e.text_subset        = st.text_subset
        and st.piece             < &&num_rows_per_hash
        and e.executions         > nvl(b.executions,0)
      order by (e.buffer_gets - nvl(b.buffer_gets,0)) desc, e.hash_value, st.piece
      )
where rownum < &&top_n_sql;



--
--  SQL statements ordered by physical reads

ttitle lef 'SQL ordered by Reads for ' -
           'DB: ' db_name  '  Instance: ' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap ' -' format 99999999 end_snap -
       skip 1 -
           '-> End Disk Reads Threshold: '   edrt -
       skip 2;

col aa format a80 heading -
'                                                     CPU      Elapsd| Physical Reads  Executions  Reads per Exec %Total Time (s)  Time (s) Hash Value |--------------- ------------ -------------- ------ -------- --------- ----------' 

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
                  lpad(e.hash_value,10)||''||
                  decode(e.module,null,st.sql_text
                                      ,rpad('Module: '||e.module,80)||st.sql_text)
                , st.sql_text) aa
          , e.hash_value hv
       from stats$sql_summary e
          , stats$sql_summary b
          , stats$sqltext     st 
      where b.snap_id(+)         = :bid
        and b.dbid(+)            = e.dbid
        and b.instance_number(+) = e.instance_number
        and b.hash_value(+)      = e.hash_value
        and b.address(+)         = e.address
        and b.text_subset(+)     = e.text_subset
        and e.snap_id            = :eid
        and e.dbid               = :dbid
        and e.instance_number    = :inst_num
        and e.hash_value         = st.hash_value 
        and e.text_subset        = st.text_subset
        and st.piece             < &&num_rows_per_hash
        and e.executions         > nvl(b.executions,0)
        and :phyr                > 0
      order by (e.disk_reads - nvl(b.disk_reads,0)) desc, e.hash_value, st.piece
      )
where rownum < &&top_n_sql;



--
--  SQL statements ordered by executions

ttitle lef 'SQL ordered by Executions for ' -
           'DB: ' db_name  '  Instance: ' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap ' -' format 99999999 end_snap -
       skip 1 -
           '-> End Executions Threshold: '   eet -
       skip 2;

col aa format a80 heading -
'                                                CPU per    Elap per| Executions   Rows Processed   Rows per Exec    Exec (s)   Exec (s)  Hash Value |------------ --------------- ---------------- ----------- ---------- ----------' 

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
                  lpad(e.hash_value,10)||' '||
                  decode(e.module,null,st.sql_text
                                      ,rpad('Module: '||e.module,80)||st.sql_text)
                , st.sql_text) aa
          , e.hash_value hv
       from stats$sql_summary e
          , stats$sql_summary b
          , stats$sqltext     st 
      where b.snap_id(+)         = :bid
        and b.dbid(+)            = e.dbid
        and b.instance_number(+) = e.instance_number
        and b.hash_value(+)      = e.hash_value
        and b.address(+)         = e.address
        and b.text_subset(+)     = e.text_subset
        and e.snap_id            = :eid
        and e.dbid               = :dbid
        and e.instance_number    = :inst_num
        and e.hash_value         = st.hash_value 
        and e.text_subset        = st.text_subset
        and st.piece             < &&num_rows_per_hash
        and e.executions         > nvl(b.executions,0)
      order by (e.executions - nvl(b.executions,0)) desc, e.hash_value, st.piece
      )
where rownum < &&top_n_sql;



--
--  SQL statements ordered by Parse Calls

ttitle lef 'SQL ordered by Parse Calls for ' -
           'DB: ' db_name  '  Instance: ' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap ' -' format 99999999 end_snap -
       skip 1 -
           '-> End Parse Calls Threshold: ' format 99999999 epc -
       skip 2;


col aa format a80 heading -
'                           % Total | Parse Calls  Executions   Parses  Hash Value |------------ ------------ -------- ----------' 
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
                  lpad(e.hash_value,10)||' '||
                  rpad(' ',34)||
                  decode(e.module,null,st.sql_text
                                      ,rpad('Module: '||e.module,80)||st.sql_text)
                , st.sql_text) aa
          , e.hash_value hv
       from stats$sql_summary e
          , stats$sql_summary b
          , stats$sqltext     st 
      where b.snap_id(+)         = :bid
        and b.dbid(+)            = e.dbid
        and b.instance_number(+) = e.instance_number
        and b.hash_value(+)      = e.hash_value
        and b.address(+)         = e.address
        and b.text_subset(+)     = e.text_subset
        and e.snap_id            = :eid
        and e.dbid               = :dbid
        and e.instance_number    = :inst_num
        and e.hash_value         = st.hash_value 
        and e.text_subset        = st.text_subset
        and st.piece             < &&num_rows_per_hash
      order by (e.parse_calls - nvl(b.parse_calls,0)) desc, e.hash_value, st.piece
      )
where rownum < &&top_n_sql;



--
--  SQL statements ordered by Sharable Memory

ttitle lef 'SQL ordered by Sharable Memory for ' -
           'DB: ' db_name  '  Instance: ' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap ' -' format 99999999 end_snap -
       skip 1 -
           '-> End Sharable Memory Threshold: ' format 99999999 esmt -
       skip 2;

col aa format a80 heading -
'Sharable Mem (b)  Executions  % Total  Hash Value |---------------- ------------ ------- ------------' 

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
                  lpad(e.hash_value,12)||' '||
                  rpad(' ',29)||
                  decode(e.module,null,st.sql_text
                                      ,rpad('Module: '||e.module,80)||st.sql_text)
                , st.sql_text) aa
          , e.hash_value hv
       from stats$sql_summary e
          , stats$sql_summary b
          , stats$sqltext     st 
      where b.snap_id(+)         = :bid
        and b.dbid(+)            = e.dbid
        and b.instance_number(+) = e.instance_number
        and b.hash_value(+)      = e.hash_value
        and b.address(+)         = e.address
        and b.text_subset(+)     = e.text_subset
        and e.snap_id            = :eid
        and e.dbid               = :dbid
        and e.instance_number    = :inst_num
        and e.hash_value         = st.hash_value 
        and e.text_subset        = st.text_subset
        and st.piece             < &&num_rows_per_hash
        and e.executions         > nvl(b.executions,0)
        and e.sharable_mem       > :esmt
      order by e.sharable_mem desc, e.hash_value, st.piece
      )
where rownum < &&top_n_sql;



--
--  SQL statements ordered by Version Count

ttitle lef 'SQL ordered by Version Count for ' -
           'DB: ' db_name  '  Instance: ' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap ' -' format 99999999 end_snap -
       skip 1 -
           '-> End Version Count Threshold: ' format 99999999 evc -
       skip 2;

col aa format a80 heading -
' Version|   Count  Executions   Hash Value |-------- ------------ ------------' 

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
                  lpad(e.hash_value,12)||' '||
                  rpad(' ',45)||
                  decode(e.module,null,st.sql_text
                                      ,rpad('Module: '||e.module,80)||st.sql_text)
                , st.sql_text) aa
          , e.hash_value hv
       from stats$sql_summary e
          , stats$sql_summary b
          , stats$sqltext     st 
      where b.snap_id(+)         = :bid
        and b.dbid(+)            = e.dbid
        and b.instance_number(+) = e.instance_number
        and b.hash_value(+)      = e.hash_value
        and b.address(+)         = e.address
        and b.text_subset(+)     = e.text_subset
        and e.snap_id            = :eid
        and e.dbid               = :dbid
        and e.instance_number    = :inst_num
        and e.hash_value         = st.hash_value 
        and e.text_subset        = st.text_subset
        and st.piece             < &&num_rows_per_hash
        and e.executions         > nvl(b.executions,0)
        and e.version_count      > :evc
      order by e.version_count desc, e.hash_value, st.piece
      )
where rownum < &&top_n_sql;

set underline '-';



--
--  Instance Activity Statistics

ttitle lef 'Instance Activity Stats for ' -
           'DB: ' db_name  '  Instance: ' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap ' -' format 99999999 end_snap -
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
                     )
   and e.value          >= b.value
   and e.value          >  0
 order by st;



--
--  Session Wait Events

ttitle lef 'Session Wait Events for ' -
           'DB: ' db_name  '  Instance: ' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap ' -' format 99999999 end_snap -
       skip 1 -
       lef 'Session Id: ' sess_id '  Serial#: ' serial -
       skip 1 -
       lef '-> ordered by wait time desc, waits desc (idle events last)' -
       skip 2;

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
--  Session Statistics

ttitle lef 'Session Statistics for ' -
           'DB: ' db_name  '  Instance: ' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap ' -' format 99999999 end_snap -
       skip 1 -
       lef 'Session Id: ' sess_id '  Serial#: ' serial -
       skip 2;


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

ttitle lef 'Tablespace IO Stats for '-
           'DB: ' db_name  '  Instance: ' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap ' -' format 99999999 end_snap -
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
union
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

ttitle lef 'File IO Stats for '-
           'DB: ' db_name  '  Instance: ' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap ' -' format 99999999 end_snap -
       skip 1 -
       lef '->ordered by Tablespace, File' -
       skip 2;

col tsname     format a24           heading 'Tablespace' trunc;
col filename   format a52           heading 'Filename'   trunc;
col reads      format 9,999,999,990 heading 'Reads'

break on tsname skip 1;

select e.tsname
     , e.filename
     , e.phyrds- nvl(b.phyrds,0)                       reads
     , (e.phyrds- nvl(b.phyrds,0))/:ela                rps
     , decode ((e.phyrds - nvl(b.phyrds, 0)), 0, to_number(NULL),
          ((e.readtim  - nvl(b.readtim,0)) /
           (e.phyrds   - nvl(b.phyrds,0)))*10)         atpr
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
   and ( (e.phyrds  - nvl(b.phyrds,0)  ) + 
         (e.phywrts - nvl(b.phywrts,0) ) ) > 0
union
select e.tsname
     , e.filename
     , e.phyrds- nvl(b.phyrds,0)                       reads
     , (e.phyrds- nvl(b.phyrds,0))/:ela                rps
     , decode ((e.phyrds - nvl(b.phyrds, 0)), 0, to_number(NULL),
          ((e.readtim  - nvl(b.readtim,0)) /
           (e.phyrds   - nvl(b.phyrds,0)))*10)         atpr
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
   and ( (e.phyrds  - nvl(b.phyrds,0)  ) + 
         (e.phywrts - nvl(b.phywrts,0) ) ) > 0
 order by tsname, filename;



--
--  Buffer pools

ttitle lef 'Buffer Pool Statistics for ' -
           'DB: ' db_name  '  Instance: ' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap ' -' format 99999999 end_snap -
       skip 1 -
       lef '-> Standard block size Pools  D: default,  K: keep,  R: recycle' -
       skip 1 -
       lef '-> Default Pools for other block sizes: 2k, 4k, 8k, 16k, 32k' -
       skip 2;

col id      format 99            heading 'Set|Id';
col name    format a3            heading 'P|---' trunc;
col buffs   format 999,999,999   heading 'Buffer|Gets|-----------';
col conget  format 9,999,999,999 heading 'Consistent|Gets|-------------';
col phread  format 999,999,999   heading 'Physical|Reads|-----------';
col phwrite format 99,999,999    heading 'Physical|Writes|----------';
col fbwait  format 999,999       heading 'Free|Buffer|Waits|-------';
col wcwait  format 999,999       heading 'Write|Complete|Waits| --------';
col bbwait  format 999,999       heading 'Buffer|Busy|Waits|------'
col poolhr  format 999.9         heading 'Cache| Hit %| -----'
col numbufs format 99,999,999    heading 'Number of|Buffers|----------'

set colsep '' underline off;

select replace(e.block_size/1024||'k', :bs/1024||'k', substr(e.name,1,1)) name
     , e.set_msize                                            numbufs
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
     , e.physical_reads      - nvl(b.physical_reads,0)	      phread
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

ttitle lef 'Instance Recovery Stats for ' -
           'DB: ' db_name  '  Instance: ' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap ' -' format 99999999 end_snap -
       skip 1 -
       '-> B: Begin snapshot,  E: End snapshot' -
       skip 2;

column tm    format       9999 heading 'Targt|MTTR|(s)' just c;
column em    format       9999 heading 'Estd|MTTR|(s)'   just c;
column beg   format a1         heading '';
column rei   format  999999999 heading 'Recovery|Estd IOs' just c;
column arb   format  999999999 heading 'Actual|Redo Blks' just c;
column trb   format  999999999 heading 'Target|Redo Blks' just c;
column lfrb  format  999999999 heading 'Log File|Size|Redo Blks' just c;
column lctrb format  999999999 heading 'Log Ckpt|Timeout|Redo Blks' just c;
column lcirb format  999999999 heading 'Log Ckpt|Interval|Redo Blks' just c;
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
union
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
     , decode(nvl(sum (case when name = 'db_cache_size'
                       then value else '0' end) , '0')
             , '0'
             , nvl(sum (case when name = 'db_block_buffers'
                        then to_char(value * :bs) else '0' end),'0')
             , sum (case when name = 'db_cache_size'
                       then value else '0' end) )       def_cache
 from stats$parameter
where name in ( 'db_2k_cache_size'     ,'db_4k_cache_size'
               ,'db_8k_cache_size'     ,'db_16k_cache_size'
               ,'db_32k_cache_size'
               ,'db_cache_size'        ,'db_block_buffers'
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

ttitle lef 'Buffer Pool Advisory for '-
           'DB: ' db_name  '  Instance: ' inst_name '  '-
           'End Snap: ' format 99999999 end_snap -
       skip 1 -
       lef '-> Only rows with estimated physical reads >0 are displayed' -
       skip 1 -
       lef '-> ordered by Block Size, Buffers For Estimate (default block size first)' -
       skip 2;

column id                        format 999;
column name                      format a3                   heading 'P' trunc;
column order_def_bs  noprint
column advice_status             format a2 trunc             heading 'ON';
column block_size                format             99999    heading 'Block|Size';
column size_for_estimate         format       999,999,999    heading 'Size for|Estimate (M)';
column buffers_for_estimate      format   999,999,999,999    heading 'Buffers for|Estimate';
column estd_physical_read_factor format         9,999,990.90 heading 'Est Physical|Read Factor';
column estd_physical_reads       format 9,999,999,999,999    heading 'Estimated|Physical Reads';
column bcsf                      format 99.9                 heading 'Size|Factr'

select replace(block_size/1024||'k', :bs/1024||'k', substr(name,1,1)) name
     , decode(block_size, :bs, 1, 2) order_def_bs
     , size_for_estimate
     , nvl(  size_factor
           , decode(  replace(block_size/1024||'k', :bs/1024||'k', substr(name,1,1))
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
     , buffers_for_estimate
     , estd_physical_read_factor
     , estd_physical_reads
  from stats$db_cache_advice
 where snap_id             = :eid
   and dbid                = :dbid
   and instance_number     = :inst_num
   and estd_physical_reads > 0
 order by order_def_bs, block_size, name, buffers_for_estimate;



set newpage 2;

--
--  Buffer waits

ttitle lef 'Buffer wait Statistics for '-
           'DB: ' db_name  '  Instance: ' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap ' -' format 99999999 end_snap -
       skip 1 -
       lef '-> ordered by wait time desc, waits desc' -
       skip 2;

column class	                        heading 'Class';
column icnt	format 99,999,990	heading 'Waits';
column itim	format  9,999,990	heading 'Tot Wait|Time (s)';
column iavg     format    999,990	heading 'Avg|Time (ms)' just c;

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

ttitle lef 'PGA Aggr Target Stats for ' -
           'DB: ' db_name  '  Instance: ' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap ' -' format 99999999 end_snap -
       skip 1 -
       lef '-> B: Begin snap   E: End snap (rows dentified with B or E contain data' -
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
union
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

ttitle lef 'PGA Aggr Target Histogram for ' -
           'DB: ' db_name  '  Instance: ' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap ' -' format 99999999 end_snap -
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

ttitle lef 'PGA Memory Advisory for '-
           'DB: ' db_name  '  Instance: ' inst_name '  '-
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

set newpage 0;



--
--  Enqueue activity

ttitle lef 'Enqueue activity for ' -
           'DB: ' db_name  '  Instance: ' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap ' -' format 99999999 end_snap -
       skip 1 -
       lef '-> Enqueue stats gathered prior to 9i should not be compared with 9i data' -
       skip 1 -
       lef '-> ordered by Wait Time desc, Waits desc' -
       skip 2;

col ename format          a2    heading 'Eq';
col reqs  format 999,999,990    heading 'Requests';
col sreq  format 999,999,990    heading 'Succ Gets';
col freq  format  99,999,990    heading 'Failed Gets';
col waits format  99,999,990    heading 'Waits';
col awttm format   9,999,999.99 heading 'Avg Wt|Time (ms)' just c;
col wttm  format 999,999,999    heading 'Wait|Time (s)'    just c;

select e.eq_type                                        ename
     , e.total_req#    - nvl(b.total_req#,0)            reqs
     , e.succ_req#     - nvl(b.succ_req#,0)             sreq
     , e.failed_req#   - nvl(b.failed_req#,0)           freq
     , e.total_wait#   - nvl(b.total_wait#,0)           waits
     , decode(  (e.total_wait#   - nvl(b.total_wait#,0))
               , 0, to_number(NULL)
               , (  (e.cum_wait_time - nvl(b.cum_wait_time,0))
                  / (e.total_wait#   - nvl(b.total_wait#,0))
                 )
             )                                          awttm
     , (e.cum_wait_time - nvl(b.cum_wait_time,0))/1000  wttm
  from stats$enqueue_stat b
     , stats$enqueue_stat e
 where b.snap_id(+)         = :bid
   and e.snap_id            = :eid
   and b.dbid(+)            = :dbid
   and e.dbid               = :dbid
   and b.dbid(+)            = e.dbid
   and b.instance_number(+) = :inst_num
   and e.instance_number    = :inst_num
   and b.instance_number(+) = e.instance_number
   and b.eq_type(+)         = e.eq_type
   and e.total_wait# - nvl(b.total_wait#,0) > 0
 order by wttm desc, waits desc;



--
--  Rollback segment

set newpage 0;

ttitle lef 'Rollback Segment Stats for ' -
           'DB: ' db_name  '  Instance: ' inst_name '  ' -
           'Snaps: ' format 99999999 begin_snap ' -' format 99999999 end_snap -
       skip 1 -
       lef '->A high value for "Pct Waits" suggests more rollback segments may be required' -
       skip 1 -
       lef '->RBS stats may not be accurate between begin and end snaps when using Auto Undo,' -
      skip 1 -
       lef '  managment, as RBS may be dynamically created and dropped as needed' -
       skip 2;

column usn      format 990	      heading 'RBS No' Just Cen;
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
 order by e.usn;


ttitle lef 'Rollback Segment Storage for '-
           'DB: ' db_name  '  Instance: ' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap ' -' format 99999999 end_snap -
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
 order by e.usn;



--
--  Undo Segment

ttitle lef 'Undo Segment Summary for ' -
           'DB: ' db_name  '  Instance: ' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap ' -' format 99999999 end_snap -
       skip 1 -
       lef '-> Undo segment block stats:' -
       skip 1 -
       lef '-> uS - unexpired Stolen,   uR - unexpired Released,   uU - unexpired reUsed' -
       skip 1 -
       lef '-> eS - expired   Stolen,   eR - expired   Released,   eU - expired   reUsed' -
       skip 2;
 
column undotsn  format           999 heading 'Undo|TS#';
column undob    format 9,999,999,999 heading 'Undo|Blocks';
column txcnt    format     9,999,999 heading 'Num|Trans';
column maxq     format       999,999 heading 'Max Qry|Len (s)';
column maxc     format     9,999,999 heading 'Max Tx|Concurcy';
column snol     format         9,999 heading 'Snapshot|Too Old';
column nosp     format         9,999 heading 'Out of|Space';
column blkst    format a13           heading 'uS/uR/uU/|eS/eR/eU' wrap;
column unst     format         9,999 heading 'Unexp|Stolen' newline;
column unrl     format         9,999 heading 'Unexp|Relesd';
column unru     format         9,999 heading 'Unexp|Reused';
column exst     format         9,999 heading 'Exp|Stolen';
column exrl     format         9,999 heading 'Exp|Releas';
column exru     format         9,999 heading 'Exp|Reused';

select undotsn
     , sum(undoblks)                undob
     , sum(txncount)                txcnt
     , max(maxquerylen)             maxq
     , max(maxconcurrency)          maxc
     , sum(ssolderrcnt)             snol
     , sum(nospaceerrcnt)           nosp
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
 group by undotsn;


set newpage 2;

ttitle lef 'Undo Segment Stats for ' -
           'DB: ' db_name  '  Instance: ' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap ' -' format 99999999 end_snap -
       skip 1 -
       lef '-> ordered by Time desc' -
       skip 2;

column undotsn  format         999 heading 'Undo|TS#' noprint;
column endt     format a12         heading 'End Time';
column undob    format 999,999,999 heading 'Undo|Blocks';
column txcnt    format     999,999 heading 'Num|Trans';
column maxq     format      99,999 heading 'Max Qry|Len (s)';
column maxc     format     999,999 heading 'Max Tx|Concy';
column snol     format         999 heading 'Snap|Too Old' just c;
column nosp     format         999 heading 'Out of|Space';
column blkst    format a13         heading 'uS/uR/uU/|eS/eR/eU' wrap;

select undotsn
     , endt
     , undob
     , txcnt
     , maxq
     , maxc
     , snol
     , nosp
     , blkst
  from (select undotsn
             , to_char(end_time,   'DD-Mon HH24:MI')    endt
             , undoblks                                 undob
             , txncount                                 txcnt
             , maxquerylen                              maxq
             , maxconcurrency                           maxc
             , ssolderrcnt                              snol
             , nospaceerrcnt                            nosp
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
         order by begin_time desc
       )
 where rownum < 35;

set newpage 0;



--
--  Latch Activity

ttitle lef 'Latch Activity for '-
           'DB: ' db_name  '  Instance: ' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap ' -' format 99999999 end_snap -
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

column name    	format a24    	        heading 'Latch' trunc;
column gets   	format 9,999,999,990	heading 'Get|Requests';
column missed   format 990.9            heading 'Pct|Get|Miss';
column sleeps	format 990.9 	        heading 'Avg|Slps|/Miss';
column nowai	format 999,999,990	heading 'NoWait|Requests';
column imiss	format 990.9 	        heading 'Pct|NoWait|Miss';
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

ttitle lef 'Latch Sleep breakdown for ' -
           'DB: ' db_name  '  Instance: ' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap ' -' format 99999999 end_snap -
       skip 1 -
       lef '-> ordered by misses desc' -
       skip 2;

column gets clear;
column name    	 format a26    	        heading 'Latch Name' trunc;
column gets   	 format 9,999,999,990	heading 'Get|Requests';
column sleeps	 format 99,999,990 	heading 'Sleeps';
column spin_gets format 99,999,990 	heading 'Spin|Gets';
column misses    format 99,999,990 	heading 'Misses';
column sleep4 	 format a12 	        heading 'Spin &|Sleeps 1->4' just c;

select b.name                                      name
     , e.gets        - b.gets                      gets
     , e.misses      - b.misses                    misses
     , e.sleeps      - b.sleeps                    sleeps
     , to_char(e.spin_gets          - b.spin_gets)
       ||'/'||to_char(e.sleep1      - b.sleep1) 
       ||'/'||to_char(e.sleep2      - b.sleep2)
       ||'/'||to_char(e.sleep3      - b.sleep3)
       ||'/'||to_char(e.sleep4      - b.sleep4)    sleep4
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

ttitle lef 'Latch Miss Sources for ' -
           'DB: ' db_name  '  Instance: ' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap ' -' format 99999999 end_snap -
       skip 1 -
       lef '-> only latches with sleeps are shown' -
       skip 1 -
       lef '-> ordered by name, sleeps desc' -
       skip 2;

column parent        format a24       heading 'Latch Name' trunc;
column where_from    format a26       heading 'Where'      trunc;
column nwmisses      format 99,990    heading 'NoWait|Misses';
column sleeps	     format 9,999,990 heading '   Sleeps';
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
           'DB: ' db_name  '  Instance: ' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap ' -' format 99999999 end_snap -
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
     , lp.sleep4
  from (select e.instance_number, e.dbid, e.snap_id, e.latch#
             , e.gets        - b.gets                      gets
             , e.misses      - b.misses                    misses
             , e.sleeps      - b.sleeps                    sleeps
             , to_char(e.spin_gets          - b.spin_gets)
               ||'/'||to_char(e.sleep1      - b.sleep1) 
               ||'/'||to_char(e.sleep2      - b.sleep2)
               ||'/'||to_char(e.sleep3      - b.sleep3)
               ||'/'||to_char(e.sleep4      - b.sleep4)    sleep4
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
           'DB: ' db_name  '  Instance: ' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap ' -' format 99999999 end_snap -
       skip 1 -
       lef '-> only latches with sleeps/gets > 1/100000 are shown' -
       skip 1 -
       lef '-> ordered by name, gets desc' -
       skip 2;

column name       format a22            heading 'Latch Name' trunc;
column child      format 999999         heading 'Child|Num';
column gets   	  format 999,999,990	heading 'Get|Requests';
column sleep4 	  format a12 	        heading 'Spin &|Sleeps 1->4' just c;

select l.name
     , lc.child
     , lc.gets
     , lc.misses
     , lc.sleeps
     , lc.sleep4
  from (select /*+ ordered use_hash(b) */
               e.instance_number, e.dbid, e.snap_id, e.latch#
             , e.child#                                    child
             , e.gets        - b.gets                      gets
             , e.misses      - b.misses                    misses
             , e.sleeps      - b.sleeps                    sleeps
             , to_char(e.spin_gets          - b.spin_gets)
               ||'/'||to_char(e.sleep1      - b.sleep1) 
               ||'/'||to_char(e.sleep2      - b.sleep2)
               ||'/'||to_char(e.sleep3      - b.sleep3)
               ||'/'||to_char(e.sleep4      - b.sleep4)    sleep4
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
--  Segment Statistics

ttitle lef 'Top &&top_n_segstat Logical Reads per Segment for DB: ' -
           db_name  '  Instance: ' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap ' -' format 99999999 end_snap -
       skip 1 -
           '-> End Segment Logical Reads Threshold: '   format 99999999 eslr -
       skip 2

column owner heading "Owner" format a10 trunc
column tablespace_name heading "Tablespace Name" format a10 trunc
column object_type heading "Obj.|Type" format a5 trunc
col ratio heading %Total format 999.99
column object_name heading "Object Name" format a20 trunc
column subobject_name heading "Subobject|Name" format a10 trunc

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
     , round(r.ratio * 100, 2) ratio
  from stats$seg_stat_obj n
     , (select *
          from (select e.dataobj#
                     , e.obj#
                     , e.dbid
                     , e.logical_reads - nvl(b.logical_reads, 0) logical_reads
                     , ratio_to_report(e.logical_reads - nvl(b.logical_reads, 0)) over () ratio
                  from stats$seg_stat e
                     , stats$seg_stat b
                 where b.snap_id (+)                              = :bid
                   and e.snap_id                                  = :eid
                   and b.dbid (+)                                 = :dbid
                   and e.dbid                                     = :dbid
                   and b.instance_number (+)                      = :inst_num
                   and e.instance_number                          = :inst_num
                   and e.obj#                                     = b.obj# (+)
                   and e.dataobj#                                 = b.dataobj# (+)
		   and e.logical_reads - nvl(b.logical_reads, 0)  > 0
                 order by logical_reads desc) d
          where rownum <= &&top_n_segstat) r
 where n.dataobj# = r.dataobj#
   and n.obj#     = r.obj#
   and n.dbid     = r.dbid
 order by logical_reads desc;

set newpage 2
ttitle lef 'Top &&top_n_segstat Physical Reads per Segment for DB: ' -
           db_name  '  Instance: ' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap ' -' format 99999999 end_snap -
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
     , round(r.ratio * 100, 2) ratio
  from stats$seg_stat_obj n
     , (select *
          from (select e.dataobj#
                     , e.obj#
                     , e.dbid
                     , e.physical_reads - nvl(b.physical_reads, 0) physical_reads
                     , ratio_to_report(e.physical_reads - nvl(b.physical_reads, 0)) over () ratio
                  from stats$seg_stat e
                     , stats$seg_stat b
                 where b.snap_id (+)                                = :bid
                   and e.snap_id                                    = :eid
                   and b.dbid (+)                                   = :dbid
                   and e.dbid                                       = :dbid
                   and b.instance_number (+)                        = :inst_num
                   and e.instance_number                            = :inst_num
                   and e.obj#                                       = b.obj# (+)
                   and e.dataobj#                                   = b.dataobj# (+)
                   and e.physical_reads - nvl(b.physical_reads, 0)  > 0
                 order by physical_reads desc) d
          where rownum <= &&top_n_segstat) r
 where n.dataobj# = r.dataobj#
   and n.obj#     = r.obj#
   and n.dbid     = r.dbid
 order by physical_reads desc;

set newpage 0
ttitle lef 'Top &&top_n_segstat Buf. Busy Waits per Segment for DB: ' -
           db_name  '  Instance: ' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap ' -' format 99999999 end_snap -
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
     , round(r.ratio * 100, 2) ratio
  from stats$seg_stat_obj n
     , (select *
          from (select e.dataobj#
                     , e.obj#
                     , e.dbid
                     , e.buffer_busy_waits - nvl(b.buffer_busy_waits, 0) buffer_busy_waits
                     , ratio_to_report(e.buffer_busy_waits - nvl(b.buffer_busy_waits, 0)) over () ratio
                  from stats$seg_stat e
                     , stats$seg_stat b
                 where b.snap_id (+)                                      = :bid
                   and e.snap_id                                          = :eid
                   and b.dbid (+)                                         = :dbid
                   and e.dbid                                             = :dbid
                   and b.instance_number (+)                              = :inst_num
                   and e.instance_number                                  = :inst_num
                   and e.obj#                                             = b.obj# (+)
                   and e.dataobj#                                         = b.dataobj# (+)
                   and e.buffer_busy_waits - nvl(b.buffer_busy_waits, 0)  > 0
                 order by buffer_busy_waits desc) d
          where rownum <= &&top_n_segstat) r
 where n.dataobj# = r.dataobj#
   and n.obj#     = r.obj#
   and n.dbid     = r.dbid
 order by buffer_busy_waits desc;

set newpage 2
ttitle lef 'Top &&top_n_segstat Row Lock Waits per Segment for DB: ' -
           db_name  '  Instance: ' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap ' -' format 99999999 end_snap -
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
     , round(r.ratio * 100, 2) ratio
  from stats$seg_stat_obj n
     , (select *
          from (select e.dataobj#
                     , e.obj#
                     , e.dbid
                     , e.row_lock_waits - nvl(b.row_lock_waits, 0) row_lock_waits
                     , ratio_to_report(e.row_lock_waits - nvl(b.row_lock_waits, 0)) over () ratio
                  from stats$seg_stat e
                     , stats$seg_stat b
                 where b.snap_id (+)                                = :bid
                   and e.snap_id                                    = :eid
                   and b.dbid (+)                                   = :dbid
                   and e.dbid                                       = :dbid
                   and b.instance_number (+)                        = :inst_num
                   and e.instance_number                            = :inst_num
                   and e.obj#                                       = b.obj# (+)
                   and e.dataobj#                                   = b.dataobj# (+)
                   and e.row_lock_waits - nvl(b.row_lock_waits, 0)  > 0
                 order by row_lock_waits desc) d
          where rownum <= &&top_n_segstat) r
 where n.dataobj# = r.dataobj#
   and n.obj#     = r.obj#
   and n.dbid     = r.dbid
 order by row_lock_waits desc;

set newpage 2
ttitle lef 'Top &&top_n_segstat ITL Waits per Segment for DB: ' -
           db_name  '  Instance: ' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap ' -' format 99999999 end_snap -
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
     , round(r.ratio * 100, 2) ratio
  from stats$seg_stat_obj n
     , (select *
          from (select e.dataobj#
                     , e.obj#
                     , e.dbid
                     , e.itl_waits - nvl(b.itl_waits, 0) itl_waits
                     , ratio_to_report(e.itl_waits - nvl(b.itl_waits, 0)) over () ratio
                  from stats$seg_stat e
                     , stats$seg_stat b
                 where b.snap_id (+)                     = :bid
                   and e.snap_id                         = :eid
                   and b.dbid (+)                        = :dbid
                   and e.dbid                            = :dbid
                   and b.instance_number (+)             = :inst_num
                   and e.instance_number                 = :inst_num
                   and e.obj#                            = b.obj# (+)
                   and e.dataobj#                        = b.dataobj# (+)
                   and e.itl_waits - nvl(b.itl_waits, 0) > 0
                 order by itl_waits desc) d
          where rownum <= &&top_n_segstat) r
 where n.dataobj# = r.dataobj#
   and n.obj#     = r.obj#
   and n.dbid     = r.dbid
 order by itl_waits desc;

set newpage 0
ttitle lef 'Top &&top_n_segstat CR Blocks Served (RAC) per Segment for DB: ' -
           db_name  '  Instance: ' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap ' -' format 99999999 end_snap -
       skip 1 -
           '-> End Global Cache CR Blocks Served Threshold: '   ecrb -
       skip 2

column cr_blocks_served heading "CR|Blocks|Served" format 999,999,999

select n.owner
     , n.tablespace_name
     , n.object_name
     , case when length(n.subobject_name) < 11 then
              n.subobject_name
            else
              substr(n.subobject_name,length(n.subobject_name)-9)
       end subobject_name
     , n.object_type
     , r.cr_blocks_served
     , round(r.ratio * 100, 2) ratio
  from stats$seg_stat_obj n
     , (select *
          from (select e.dataobj#
                     , e.obj#
                     , e.dbid
                     , e.global_cache_cr_blocks_served - nvl(b.global_cache_cr_blocks_served, 0) cr_blocks_served
                     , ratio_to_report(e.global_cache_cr_blocks_served - nvl(b.global_cache_cr_blocks_served, 0)) over () ratio
                  from stats$seg_stat e
                     , stats$seg_stat b
                 where b.snap_id (+)     							 = :bid
                   and e.snap_id         							 = :eid
                   and b.dbid (+)        							 = :dbid
                   and e.dbid            							 = :dbid
                   and b.instance_number (+)                                                     = :inst_num
                   and e.instance_number 							 = :inst_num
                   and e.obj#            							 = b.obj# (+)
                   and e.dataobj#        							 = b.dataobj# (+)
                   and e.global_cache_cr_blocks_served - nvl(b.global_cache_cr_blocks_served, 0) > 0
                 order by cr_blocks_served desc) d
          where rownum <= &&top_n_segstat) r
 where n.dataobj# = r.dataobj#
   and n.obj#     = r.obj#
   and n.dbid     = r.dbid
   and :para      ='YES'
 order by cr_blocks_served desc;

set newpage 2
ttitle lef 'Top &&top_n_segstat CU Blocks Served (RAC) per Segment for DB: ' -
           db_name  '  Instance: ' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap ' -' format 99999999 end_snap -
       skip 1 -
           '-> End Global Cache CU Blocks Served Threshold: '   ecub -
       skip 2

column cu_blocks_served heading "CU|Blocks|Served" format 999,999,999

select n.owner
     , n.tablespace_name
     , n.object_name
     , case when length(n.subobject_name) < 11 then
              n.subobject_name
            else
              substr(n.subobject_name,length(n.subobject_name)-9)
       end subobject_name
     , n.object_type
     , r.cu_blocks_served
     , round(r.ratio * 100, 2) ratio
  from stats$seg_stat_obj n
     , (select *
          from (select e.dataobj#
                     , e.obj#
                     , e.dbid
                     , e.global_cache_cu_blocks_served - nvl(b.global_cache_cu_blocks_served, 0) cu_blocks_served
                     , ratio_to_report(e.global_cache_cu_blocks_served - nvl(b.global_cache_cu_blocks_served, 0)) over () ratio
                  from stats$seg_stat e
                     , stats$seg_stat b
                 where b.snap_id (+)     							 = :bid
                   and e.snap_id         							 = :eid
                   and b.dbid (+)        							 = :dbid
                   and e.dbid            							 = :dbid
                   and b.instance_number (+)				 = :inst_num
                   and e.instance_number 							 = :inst_num
                   and e.obj#            							 = b.obj# (+)
                   and e.dataobj#        							 = b.dataobj# (+)
                   and e.global_cache_cu_blocks_served - nvl(b.global_cache_cu_blocks_served, 0) > 0
                 order by cu_blocks_served desc) d
          where rownum <= &&top_n_segstat) r
 where n.dataobj# = r.dataobj#
   and n.obj#     = r.obj#
   and n.dbid     = r.dbid
   and :para      ='YES'
 order by cu_blocks_served desc;


set newpage 0
--
--  Dictionary Cache

ttitle lef 'Dictionary Cache Stats for ' -
           'DB: ' db_name  '  Instance: ' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap ' -' format 99999999 end_snap -
       skip 1 -
       lef '->"Pct Misses"  should be very low (< 2% in most cases)'-
       skip 1 -
       lef '->"Cache Usage" is the number of cache entries being used'-
       skip 1 -
       lef '->"Pct SGA"     is the ratio of usage to allocated size for that cache'-
       skip 2;

column param	format a25 	heading 'Cache'  trunc;
column gets	format 999,999,990	heading 'Get|Requests';
column getm	format 990.9	heading 'Pct|Miss';
column scans	format 99,990	heading 'Scan|Reqs';
column scanm	format 90.9	heading 'Pct|Miss';
column mods	format  999,990	heading 'Mod|Reqs';
column usage	format 9,999,990	heading 'Final|Usage';

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
   and :para             = 'YES'
 order by param;



--
--  Library Cache

set newpage 2;
ttitle lef 'Library Cache Activity for '-
           'DB: ' db_name  '  Instance: ' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap ' -' format 99999999 end_snap -
       skip 1 -
           '->"Pct Misses"  should be very low  ' skip 2;

column namespace                      heading 'Namespace';
column gets	format 999,999,990    heading 'Get|Requests';
column pins	format 9,999,999,990  heading 'Pin|Requests' just c;
column getm	format 990.9	      heading 'Pct|Miss' just c;
column pinm	format 990.9	      heading 'Pct|Miss' just c;
column reloads  format 9,999,990      heading 'Reloads';
column inv      format 999,990        heading 'Invali-|dations';

select b.namespace
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
   and b.dbid            = :dbid
   and e.dbid            = :dbid
   and b.dbid            = e.dbid
   and b.instance_number = :inst_num
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

select b.namespace
     , e.dlm_lock_requests - b.dlm_lock_requests               dlreq
     , e.dlm_pin_requests  - b.dlm_pin_requests                dpreq
     , e.dlm_pin_releases  - b.dlm_pin_releases                dprel
     , e.dlm_invalidation_requests - b.dlm_invalidation_requests direq
     , e.dlm_invalidations - b.dlm_invalidations               dinv
  from stats$librarycache b
     , stats$librarycache e
 where b.snap_id         = :bid   
   and e.snap_id         = :eid
   and b.dbid            = :dbid
   and e.dbid            = :dbid
   and b.dbid            = e.dbid
   and b.instance_number = :inst_num
   and e.instance_number = :inst_num
   and b.instance_number = e.instance_number
   and b.namespace       = e.namespace
   and e.gets - b.gets   > 0
   and :para             = 'YES';

set newpage 0;



--
--  Shared Pool Advisory

ttitle lef 'Shared Pool Advisory for '-
           'DB: ' db_name  '  Instance: ' inst_name '  '-
           'End Snap: ' format 99999999 end_snap -
       skip 1 -
       lef '-> Note there is often a 1:Many correlation between a single logical object' -
       skip 1 -
       lef '   in the Library Cache, and the physical number of memory objects associated' -
       skip 1 - 
       lef '   with it.  Therefore comparing the number of Lib Cache objects (e.g. in ' -
       skip 1 -
       lef '   v$librarycache), with the number of Lib Cache Memory Objects is invalid' - 
       skip 2;

column ast    format a2 trunc             heading 'ON';
column spsfe  format      9,999,999    heading 'Shared Pool|Size for|Estim (M)';
column spsf   format             99.0  heading 'SP|Size|Factr';
column elcs   format      9,999,990    heading 'Estd|Lib Cache|Size (M)';
column elcmo  format    999,999,999    heading 'Estd|Lib Cache|Mem Obj';
column elcts  format    999,999,999    heading 'Estd Lib|Cache Time|Saved (s)';
column elctsf format             99.0  heading 'Estd|LC Time|Saved|Factr';
column elcmoh format 99,999,999,999    heading 'Estd Lib Cache|Mem Obj Hits';

select shared_pool_size_for_estimate spsfe
     , shared_pool_size_factor       spsf
     , estd_lc_size                  elcs
     , estd_lc_memory_objects        elcmo
     , estd_lc_time_saved            elcts
     , estd_lc_time_saved_factor     elctsf
     , estd_lc_memory_object_hits    elcmoh
  from stats$shared_pool_advice
 where snap_id             = :eid
   and dbid                = :dbid
   and instance_number     = :inst_num
 order by shared_pool_size_for_estimate;



--
--  SGA

column name	format a30	  heading 'SGA regions';
column value	format 999,999,999,990 heading 'Size in Bytes';

break on report;
compute sum of value on report;
ttitle lef 'SGA Memory Summary for ' -
           'DB: ' db_name  '  Instance: ' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap ' -' format 99999999 end_snap -
       skip 2;

select name
     , value
  from stats$sga
 where snap_id         = :eid
   and dbid            = :dbid
   and instance_number = :inst_num
 order by name;
clear break compute;

set newpage 2;

ttitle lef 'SGA breakdown difference for '-
           'DB: ' db_name  '  Instance: ' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap ' -' format 99999999 end_snap -
       skip 2;

column pool  format a6                 heading 'Pool' trunc ;
column name  format a30                heading 'Name';
column snap1 format 999,999,999,999    heading 'Begin value';
column snap2 format 999,999,999,999    heading 'End value';
column diff  format             990.90 heading '% Diff';

select replace(b.pool,'pool','')       pool
     , b.name                          name
     , b.bytes                         snap1
     , e.bytes                         snap2
     , 100*(e.bytes - b.bytes)/b.bytes diff
  from stats$sgastat b
     , stats$sgastat e
 where e.snap_id         = :eid
   and b.snap_id         = :bid
   and b.dbid            = :dbid
   and e.dbid            = :dbid
   and b.dbid            = e.dbid
   and b.instance_number = :inst_num
   and e.instance_number = :inst_num
   and b.instance_number = e.instance_number
   and b.name            = e.name
   and nvl(b.pool, 'a')  = nvl(e.pool, 'a')   
 order by b.pool, b.name;

set newpage 0;



--
--  Resource Limit

ttitle lef 'Resource Limit Stats for '-
           'DB: ' db_name  '  Instance: ' inst_name '  '-
           'End Snap: ' format 99999999 end_snap -
       skip 1 -
       lef '-> only rows with Current or Maximum Utilization > 80% of Limit are shown' -
       skip 1 -
       lef '-> ordered by resource name' -
       skip 2;

column rname	format a30 	        heading 'Resource Name';
column curu	format 999,999,990	heading 'Current|Utilization' just c;
column maxu	format 999,999,990	heading 'Maximum|Utilization' just c;
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



--
--  Initialization Parameters

column name     format a29      heading 'Parameter Name'         trunc;
column bval     format a33      heading 'Begin value'            trunc;
column eval     format a14      heading 'End value|(if different)' trunc just c;
 
ttitle lef 'init.ora Parameters for '-
           'DB: ' db_name  '  Instance: ' inst_name '  '-
           'Snaps: ' format 99999999 begin_snap ' -' format 99999999 end_snap -
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
   and (   nvl(b.isdefault, 'X')   = 'FALSE'
        or nvl(b.ismodified,'X')  != 'FALSE'
        or     e.ismodified       != 'FALSE'
        or nvl(e.value,0)         != nvl(b.value,0)
       )
 order by e.name;

prompt
prompt                                 End of Report 
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
undefine report_name
undefine top_n_sql
undefine top_n_events
undefine btime
undefine etime
whenever sqlerror continue;
--
--  End of script file;
