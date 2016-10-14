col name format a30
col value format a8
col description format a40 word_wrapped
set verify off
SELECT x.ksppinm name, y.ksppstvl value, x.ksppdesc description
FROM x$ksppi x, x$ksppcv y
WHERE x.inst_id = userenv('Instance')
AND y.inst_id = userenv('Instance')
AND x.indx = y.indx
AND x.ksppinm LIKE '&hidden_parameter_name';


col name format a30
col value format a8
col description format a40 word_wrapped
set verify off
SELECT x.ksppinm name, y.ksppstvl value, x.ksppdesc description
FROM x$ksppi x, x$ksppsv y
WHERE x.inst_id = userenv('Instance')
AND y.inst_id = userenv('Instance')
AND x.indx = y.indx
AND x.ksppinm LIKE '&hidden_parameter_name';

