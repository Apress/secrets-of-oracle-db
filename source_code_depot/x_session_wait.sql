CREATE OR REPLACE view x_$session_wait AS
SELECT s.inst_id AS inst_id,
s.indx AS sid,
se.ksuseser AS serial#,
-- spid from v$process
p.ksuprpid AS spid,
-- columns from v$session
se.ksuudlna AS username,
decode(bitand(se.ksuseidl,11),1,'ACTIVE',0, decode(bitand(se.ksuseflg,4096),0,'INACTIVE','CACHED'),2,'SNIPED',3,'SNIPED', 'KILLED') AS status,
decode(ksspatyp,1,'DEDICATED',2,'SHARED',3,'PSEUDO','NONE') AS server,
se.ksuseunm AS osuser,
se.ksusepid AS process,
se.ksusemnm AS machine,
se.ksusetid AS terminal,
se.ksusepnm AS program,
decode(bitand(se.ksuseflg,19),17,'BACKGROUND',1,'USER',2,'RECURSIVE','?') AS type,
se.ksusesqh AS sql_hash_value,
se.ksusepha AS prev_hash_value,
se.ksuseapp AS module,
se.ksuseact AS action,
se.ksuseclid AS client_identifier,
se.ksuseobj AS row_wait_obj#,
se.ksusefil AS row_wait_file#,
se.ksuseblk AS row_wait_block#,
se.ksuseslt AS row_wait_row#,
se.ksuseltm AS logon_time,
se.ksusegrp AS resource_consumer_group,
-- columns from v$session_wait
s.ksussseq AS seq#,
e.kslednam AS event,
e.ksledp1 AS p1text,
s.ksussp1 AS p1,
s.ksussp1r AS p1raw,
e.ksledp2 AS p2text,
s.ksussp2 AS p2,
s.ksussp2r AS p2raw,
e.ksledp3 AS p3text,
s.ksussp3 AS p3,
s.ksussp3r AS p3raw,
-- improved timing information from x$ksusecst
decode(s.ksusstim, 
-2, 'WAITED UNKNOWN TIME',
-1,'LAST WAIT < 1 microsecond', -- originally WAITED SHORT TIME
0,'CURRENTLY WAITING SINCE '|| s.ksusewtm || ' s', 
'LAST WAIT ' || s.ksusstim/1000 || ' ms (' || s.ksusewtm || ' s ago)') wait_status,
to_number(decode(s.ksusstim,0,NULL,-1,NULL,-2,NULL, s.ksusstim/1000)) AS wait_time_milli
from x$ksusecst s, x$ksled e , x$ksuse se, x$ksupr p
where bitand(s.ksspaflg,1)!=0 
and bitand(s.ksuseflg,1)!=0
and s.ksussseq!=0 
and s.ksussopc=e.indx
and s.indx=se.indx
and se.ksusepro=p.addr;

SELECT sid, serial#, spid, username, program, module, action, client_identifier, event, wait_status, wait_time_milli
FROM x_$session_wait w
WHERE w.type='USER'
ORDER BY wait_time_milli;

GRANT SELECT ON x_$session_wait TO site_sys WITH GRANT OPTION;
CREATE OR REPLACE VIEW site_sys.cgv_$session_wait AS SELECT * FROM sys.x_$session_wait;
CREATE OR REPLACE VIEW site_sys.cv_$session_wait AS SELECT * FROM sys.x_$session_wait WHERE inst_id=userenv('instance');
GRANT SELECT ON site_sys.cgv_$session_wait TO select_catalog_role;
GRANT SELECT ON site_sys.cv_$session_wait TO select_catalog_role;
CREATE OR REPLACE PUBLIC SYNONYM cgv$session_wait FOR site_sys.cgv_$session_wait;
CREATE OR REPLACE PUBLIC SYNONYM cv$session_wait FOR site_sys.cv_$session_wait;

SELECT * FROM cgv$session_wait;
SELECT * FROM cv$session_wait;
