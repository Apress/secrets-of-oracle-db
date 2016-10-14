/*
RCS keywords:
$Header: /cygdrive/c/home/ndebes/it/sql/RCS/snap_by_cpu_util.sql,v 1.3 2007/08/21 22:26:05 ndebes Exp ndebes $
$Log: snap_by_cpu_util.sql,v $
Revision 1.3  2007/08/21 22:26:05  ndebes
based on view site_sys.sp_valid_intervals

Revision 1.2  2007/08/21 10:03:56  ndebes
added some more comments

Revision 1.1  2007/08/21 09:57:49  ndebes
Initial revision


CPU utilization per snapshot normalized by second and cpu_count
1. Get CPU used by this session (unit is centiseconds) in snapshot interval (STATS$SYSSTAT) and convert to seconds. To get CPU consumption in the snapshot interval, the value captured by the start snapshot has to be subtracted from the value capture by the end snapshot.
2. Divide the CPU consumption by the snapshot interval in seconds (LAG analytic function, STATS$SNAPSHOT) 
3. Divide the result by the number of CPUs (parameter cpu_count) captured at the beginning of the snapshot interval (STATS$PARAMETER) to get average CPU utilization as a percentage of CPU capacity. Capacity is 1 second of CPU time per CPU per second)

Verification of calculation
===========================

Generate Statspack report and extract relevant numbers. Report excerpts are below:

            Snap Id     Snap Time      Sessions Curs/Sess Comment
            ------- ------------------ -------- --------- -------
Begin Snap:      90 15-Aug-07 09:35:21      215      11.9
  End Snap:      91 15-Aug-07 09:57:24      177      10.6
   Elapsed:               22.05 (mins)

Statistic                                      Total     per Second    per Trans
--------------------------------- ------------------ -------------- ------------
CPU used by this session                      82,337           62.2         23.0

The unit of CPU used by this session is centiseconds.
Note that the value of cpu_count is captured but not printed at the end of the Statspack report, since it has a default value. 
SQL> SELECT value FROM stats$parameter WHERE name='cpu_count' and snap_id=90;
VALUE
-----------------------------------------------------------------------------
4

So CPU utilization percentage is: CPU used by this session in secs / (snapshot interval in secs) / cpu_count * 100
(82337/100) / (22.05 * 60) / 4 * 100 = 15.56

The following query automates this calculation:

Except for a small error due to rounding, the result matches output of the SELECT statement:
 Start    End
SnapID SnapID Start Time          End Time            Interval (s) CPU Utilization (%)
------ ------ ------------------- ------------------- ------------ -------------------
    90     91 15.08.2007 09:35:21 15.08.2007 09:57:24         1323               15.56
    88     89 15.08.2007 06:37:42 15.08.2007 07:27:28         2986                7.14
    87     88 15.08.2007 06:06:04 15.08.2007 06:37:42         1898                5.28


*/
column interval heading "Interval (s)"
column start_snap_id format 99999 heading "Start|SnapID"
column end_snap_id format 99999 heading "End|SnapID"
column cpu_utilization format 9999.99 heading "CPU Utilization (%)"
column start_snap_time heading "Start Time"
column end_snap_time heading "End Time"
set lines 120

SELECT i.start_snap_id, i.end_snap_id, 
i.start_snap_time, i.end_snap_time,
(i.end_snap_time - i.start_snap_time) * 86400 AS interval,
round(( (s2.value - s1.value)/ 100 / ((i.end_snap_time - i.start_snap_time) * 86400 ) / p.value) * 100,2) AS cpu_utilization
FROM site_sys.sp_valid_intervals i, stats$sysstat s1, stats$sysstat s2, stats$parameter p
WHERE i.start_snap_id=s1.snap_id
AND i.end_snap_id=s2.snap_id
AND s1.name='CPU used by this session'
AND s1.name=s2.name
AND p.snap_id=i.start_snap_id
AND p.name='cpu_count'
ORDER BY cpu_utilization DESC;

