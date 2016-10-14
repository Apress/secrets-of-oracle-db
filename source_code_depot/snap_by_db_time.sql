/*
RCS keywords:
$Header: /cygdrive/c/home/ndebes/it/sql/RCS/snap_by_db_time.sql,v 1.1 2007/08/21 22:22:06 ndebes Exp ndebes $
$Log: snap_by_db_time.sql,v $
Revision 1.1  2007/08/21 22:22:06  ndebes
Initial revision


Note: script will not work against 9i and earlier releases of Statspack Repository

According to Oracle10g Database Reference:
DB Time is the amount of elapsed time (in microseconds) spent performing Database user-level calls.
This does not include the time spent on instance background processes such as PMON.

The manual states that DB time includes the following:
DB CPU
connection management call elapsed time
sequence load elapsed time
sql execute elapsed time
parse time elapsed
PL/SQL execution elapsed time
inbound PL/SQL rpc elapsed time
PL/SQL compilation elapsed time
Java execution elapsed time

Verification of Calculation
===========================

Snapshot       Snap Id     Snap Time      Sessions Curs/Sess Comment
~~~~~~~~    ---------- ------------------ -------- --------- -------
Begin Snap:         51 21-Aug-07 11:26:16       19      12.7
  End Snap:         52 21-Aug-07 11:27:31       19      13.8

Time Model System Stats  DB/Inst: ORCL/orcl  Snaps: 51-52
-> Ordered by % of DB time desc, Statistic name

Statistic                                       Time (s) % of DB time
----------------------------------- -------------------- ------------
DB time                                            153.5

153.5/75=2.046

 Start    End                                           Interval
  Snap   Snap PREV_SNAP_TIME      SNAP_TIME                  (s) DB time/s
------ ------ ------------------- ------------------- ---------- ---------
    51     52 21.08.2007 11:26:16 21.08.2007 11:27:31         75      2.05
    52     53 21.08.2007 11:27:31 21.08.2007 11:28:45         74       .61
    41     42 20.08.2007 17:03:37 20.08.2007 17:03:52         15       .32
    33     34 29.07.2007 18:55:25 29.07.2007 18:55:48         23       .15
    36     37 29.07.2007 21:00:58 29.07.2007 21:01:16         18       .08


*/
alter session set nls_date_format='dd.mm.yy hh24:mi';
column interval heading "Interval (s)"
column start_snap_id format 99999 heading "Start|SnapID"
column end_snap_id format 99999 heading "End|SnapID"
column db_time_per_sec format 9999.99 heading "DB time/s"
column start_snap_time heading "Start Time"
column end_snap_time heading "End Time"
SELECT i.start_snap_id, i.end_snap_id, 
i.start_snap_time, i.end_snap_time,
(i.end_snap_time - i.start_snap_time) * 86400 AS interval,
round((s2.value - s1.value) / 1000000 /* convert from microsec to sec */
/ ((i.end_snap_time - i.start_snap_time) * 86400 ), 2) /* normalize by snapshot interval */
AS db_time_per_sec
FROM site_sys.sp_valid_intervals i, stats$sys_time_model s1, stats$sys_time_model s2, stats$time_model_statname n
WHERE i.start_snap_id=s1.snap_id
AND i.end_snap_id=s2.snap_id
AND n.stat_name='DB time'
AND s1.stat_id=n.stat_id
AND s2.stat_id=n.stat_id
ORDER BY db_time_per_sec DESC;

---------------
-- proof that wait time is rolled up in sql execute elapsed time
SELECT stat_name, value/1000000 time_secs FROM v$sess_time_model 
WHERE (stat_name IN ('sql execute elapsed time','PL/SQL execution elapsed time')
	OR stat_name like 'DB%')
AND sid=userenv('sid');

STAT_NAME                                                         TIME_SECS
---------------------------------------------------------------- ----------
DB time                                                             .018276
DB CPU                                                              .038276
sql execute elapsed time                                            .030184
PL/SQL execution elapsed time                                       .007097

SQL> EXECUTE dbms_system.wait_for_event('db file scattered read', 1, 1);

PL/SQL procedure successfully completed.

SELECT stat_name, value/1000000 time_secs FROM v$sess_time_model 
WHERE (stat_name IN ('sql execute elapsed time','PL/SQL execution elapsed time')
	OR stat_name like 'DB%')
AND sid=userenv('sid');

STAT_NAME                                                         TIME_SECS
---------------------------------------------------------------- ----------
DB time                                                            1.030818
DB CPU                                                              .045174
sql execute elapsed time                                           1.017276
PL/SQL execution elapsed time                                       .987208

treated as if sql statement had waited for db file scattered read

PL/SQL lock timer

ges remote message
EXECUTE dbms_system.wait_for_event('ges remote message', 1, 1);

Snapshot       Snap Id     Snap Time      Sessions Curs/Sess Comment
~~~~~~~~    ---------- ------------------ -------- --------- -------------------
Begin Snap:         83 06-Sep-07 17:04:06       24       3.3
  End Snap:         84 06-Sep-07 17:09:54       24       3.3
   Elapsed:                5.80 (mins)

Time Model System Stats  DB/Inst: TEN/TEN1  Snaps: 83-84
-> Ordered by % of DB time desc, Statistic name

Statistic                                       Time (s) % of DB time
----------------------------------- -------------------- ------------
sql execute elapsed time                           319.3        100.0
PL/SQL execution elapsed time                      316.7         99.2
DB CPU                                             301.4         94.4
...
DB time                                            319.3

 Start    End
SnapID SnapID Start Time     End Time       Interval (s) DB time/s
------ ------ -------------- -------------- ------------ ---------
    83     84 06.09.07 17:04 06.09.07 17:09          348       .92
    49     50 05.09.07 07:45 05.09.07 08:00          850       .02
    25     26 25.07.07 19:53 25.07.07 20:00          401       .01

