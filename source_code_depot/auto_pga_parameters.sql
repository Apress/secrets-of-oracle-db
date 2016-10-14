col name format a20
col value format 99999999 heading "Value (KB)"
col description format a45 word_wrapped
set verify off
set lines 83
SELECT x.ksppinm name, 
CASE WHEN x.ksppinm like '%pga%' THEN to_number(y.ksppstvl)/1024
ELSE to_number(y.ksppstvl)
END AS value,
x.ksppdesc description
FROM x$ksppi x, x$ksppcv y
WHERE x.inst_id = userenv('Instance')
AND y.inst_id = userenv('Instance')
AND x.indx = y.indx
AND x.ksppinm IN ('pga_aggregate_target', '_pga_max_size', '_smm_max_size', '_smm_px_max_size');
