SELECT DISTINCT o.owner, o.object_name index_name
FROM dba_objects o, stats$sql_plan p
WHERE o.object_id=p.object#
AND o.object_type='INDEX'
AND o.owner='&owner';
