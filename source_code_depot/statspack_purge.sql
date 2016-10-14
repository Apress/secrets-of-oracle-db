-- run as sys
grant select on dba_tab_columns to perfstat;

create or replace procedure perfstat.statspack_purge (p_snap_time date)
-- delete all snapshots that were taken before the date passed with
p_snap_time (i.e. older than p_snap_time)
-- sppurge from Oracle used as a starting point for this procedure
-- some simplification was done in delete from stats$sqltext
-- verified that spreport produced exactly the same result for one a set of
snapshots before and after the purge
AS
        stmt varchar2(512);
        max_snap_id number;
BEGIN
        SELECT max(snap_id) INTO max_snap_id
        FROM stats$snapshot
        WHERE snap_time < p_snap_time;
        dbms_output.put_line('max_snap_id: '||max_snap_id);

        IF max_snap_id IS NOT NULL THEN
                DELETE FROM stats$snapshot WHERE snap_id BETWEEN 1 AND
max_snap_id;
                execute immediate 'alter session set
hash_area_size=1048576';
                delete /*+ index_ffs(st) */
                from stats$sqltext st
                where (hash_value, text_subset) not in
                        (select /*+ hash_aj full(ss) no_expand */
hash_value, text_subset
                                from stats$sql_summary ss
                                where snap_id > max_snap_id
                        )
                ;
        END IF;
        COMMIT;
END;
/
show errors

/*
exec perfstat.statspack_purge(sysdate - 30);
exec perfstat.statspack_purge(to_date('01 Feb 2005', 'dd mon yyyy'));
@?/rdbms/admin/spreport
*/

