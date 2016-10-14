-- run as SYS
GRANT SELECT ON obj$ TO site_sys WITH GRANT OPTION;
GRANT SELECT ON ind$ TO site_sys WITH GRANT OPTION;
GRANT SELECT ON object_usage TO site_sys WITH GRANT OPTION;
GRANT SELECT ON user$ TO site_sys WITH GRANT OPTION;
/* remove privileges */
DROP VIEW site_sys.index_usage; 
CREATE OR REPLACE VIEW site_sys.index_usage
    (owner,
     INDEX_NAME,
     TABLE_NAME,
     MONITORING,
     USED,
     START_MONITORING,
     END_MONITORING)
AS
SELECT u.name, io.name index_name, t.name table_name,
       decode(bitand(i.flags, 65536), 0, 'NO', 'YES'),
       decode(bitand(ou.flags, 1), 0, 'NO', 'YES'),
       ou.start_monitoring,
       ou.end_monitoring
FROM sys.obj$ io, sys.obj$ t, sys.ind$ i, sys.user$ u, sys.object_usage ou
WHERE io.owner# = t.owner#
AND io.owner# = u.user#
AND i.obj# = ou.obj#
AND io.obj# = ou.obj#
AND t.obj# = i.bo#;

-- have to grant to public, to allow non DBAs access to the view
-- which is used by function MONITOR_SCHEMA_INDEXES, which runs with
-- AUTHID CURRENT_USER
GRANT SELECT ON site_sys.index_usage TO PUBLIC;
