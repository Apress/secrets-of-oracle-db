-- run script as SYS
GRANT SELECT ON perfstat.stats$snapshot TO site_sys;
CREATE OR REPLACE VIEW site_sys.sp_valid_intervals AS
SELECT * 
FROM (
	SELECT lag(dbid) over (order by dbid, instance_number, snap_id) AS start_dbid, dbid AS end_dbid, 
	lag(snap_id) over (order by dbid, instance_number, snap_id) AS start_snap_id, snap_id AS end_snap_id, 
	lag(instance_number) over (order by dbid, instance_number, snap_id) AS start_inst_nr, instance_number AS end_inst_nr, 
	lag(snap_time) over (order by dbid, instance_number, snap_id) AS start_snap_time, snap_time AS end_snap_time, 
	lag(startup_time) over (order by dbid, instance_number, snap_id) AS start_startup_time, startup_time AS end_startup_time
	FROM perfstat.stats$snapshot
) iv
WHERE iv.start_snap_id IS NOT NULL
AND iv.start_dbid=iv.end_dbid
AND iv.start_inst_nr=iv.end_inst_nr
AND iv.start_startup_time=iv.end_startup_time;

SELECT start_snap_id, end_snap_id, start_inst_nr, start_snap_time, trunc((end_snap_time-start_snap_time)*86400) AS interval
FROM site_sys.sp_valid_intervals;

/*
START_SNAP_ID END_SNAP_ID START_INST_NR START_SNAP_TIME       INTERVAL
------------- ----------- ------------- ------------------- ----------
           85          86             1 15.08.2007 05:30:37        601
           86          87             1 15.08.2007 05:40:38       1526
           87          88             1 15.08.2007 06:06:04       1898
           88          89             1 15.08.2007 06:37:42       2986
           90          91             1 15.08.2007 09:35:21       1323


START_SNAP_ID END_SNAP_ID START_INST_NR END_INST_NR START_SNAP_TIME
------------- ----------- ------------- ----------- -------------------
          101         102             1           1 30.07.2007 07:22:28
          102         103             1           1 30.07.2007 07:22:56
          107         108             2           2 06.08.2007 11:31:35
          108         109             2           2 06.08.2007 11:43:58
          109         110             2           2 06.08.2007 11:47:16

*/
