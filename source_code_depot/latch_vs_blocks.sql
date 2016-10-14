SELECT bh.file#, bh.dbablk, bh.class, decode(bh.state,0,'free',1,'xcur',2,'scur',3,'cr', 4,'read',5,'mrec',6,'irec',7,'write',8,'pi', 9,'memory',10,'mwrite',11,'donated') AS status, decode(bitand(bh.flag,1), 0, 'N', 'Y') AS dirty, bh.tch,
	o.owner, o.object_name, o.object_type
FROM x$bh bh, dba_objects o
WHERE bh.obj=o.data_object_id
AND bh.hladdr='&child_latch_address'
ORDER BY tch DESC;
