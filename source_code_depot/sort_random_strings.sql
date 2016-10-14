SELECT sid, server FROM v$session WHERE audsid=userenv('sessionid');
set timing on
set autotrace traceonly statistics
SELECT * FROM random_strings ORDER BY 1;
exit
