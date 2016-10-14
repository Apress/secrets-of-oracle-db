SET LONG 1048576
SET PAGESIZE 9999
COLUMN sql_text FORMAT a64 WORD_WRAPPED
SELECT sql_id, sql_text
FROM dba_hist_sqltext
WHERE dbms_lob.instr(sql_text, '&pattern', 1, 1) > 0;

