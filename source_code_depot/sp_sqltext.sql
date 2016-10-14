-- $Header: /cygdrive/c/home/ndebes/it/sql/RCS/stats_sqltext.sql,v 1.1 2006/07/13 00:58:44 ndebes Exp ndebes $
-- run as a DBA user
-- objects are created in schema site_sys, since SYS is reserved for the data dictionary and
-- objects in schema SYS are not covery be a full export

CREATE USER site_sys IDENTIFIED BY secret PASSWORD EXPIRE ACCOUNT LOCK;

-- note that show errors does not work when creating objects in a foreign schema. If you get errors
-- either run this script as site_sys after unlocking the account or access DBA_ERRORS as below:
-- col text format a66
-- SELECT line,text from dba_errors where name='SP_SQLTEXT' ORDER BY line;

-- cleanup, e.g. for database upgraded to 10g
begin
	execute immediate 'DROP SYNONYM site_sys.stats$sqltext';
	execute immediate 'DROP VIEW site_sys.stats$sqltext';
exception when others then null;
end;
/

GRANT SELECT ON perfstat.stats$sqltext TO site_sys;

create or replace type site_sys.sqltext_type as object (
	hash_value number,
	sql_text clob
);
/
show errors

create or replace type site_sys.sqltext_type_tab as table of sqltext_type;
/
show errors

-- in 10g column hash_value in STATS$SQLTEXT was renamed to old_hash_value
-- due to likewise rename in V$SQL and V$SQLTEXT and others.
-- use a synonym in 9i and a view in 10g to compensate for this
-- thus the code of function stmt_text can remain constant for 
-- both releases and dynamic SQL with DBMS_SQL must not be used
-- for 9i CREATE OR REPLACE SYNONYM site_sys.stats$sqltext FOR perfstat.stats$sqltext;
-- for 10g, create this viww:
-- CREATE OR REPLACE VIEW site_sys.stats$sqltext(hash_value, piece, sql_text) AS
-- SELECT old_hash_value, piece, sql_text FROM perfstat.stats$sqltext;

declare
	version varchar2(30);
	compatibility varchar2(30);
begin
        dbms_utility.db_version(version, compatibility);
	if to_number(substr(version,1,2)) >= 10 then
		execute immediate 'CREATE OR REPLACE VIEW site_sys.stats$sqltext
			(hash_value, piece, sql_text) AS
			SELECT old_hash_value, piece, sql_text 
			FROM perfstat.stats$sqltext';
	else
		execute immediate 'CREATE OR REPLACE SYNONYM site_sys.stats$sqltext 
			FOR perfstat.stats$sqltext';
	end if;
end;
/

/*
	p_hash_value is either the hash value of a specific statement in 
	STATS$SQLTEXT to retrieve or NULL.
	When NULL, all statements in the Statspack repository are retrieved.
	column is called old_hash_value in 10g
*/
CREATE OR REPLACE function site_sys.sp_sqltext(p_hash_value number default null) 
RETURN sqltext_type_tab PIPELINED
AS
	result_row sqltext_type:=sqltext_type(null, empty_clob);
	cursor single_stmt(p_hash_value number) is
	select hash_value, piece, sql_text from stats$sqltext
	where p_hash_value=hash_value
	order by piece;

	cursor multi_stmt is
	select hash_value, piece, sql_text from stats$sqltext
	order by hash_value, piece;
	v_sql_text stats$sqltext.sql_text%TYPE;
	v_piece binary_integer;
	v_prev_hash_value number:=NULL;
	v_cur_hash_value number:=0;
	
BEGIN
	dbms_lob.CREATETEMPORARY(result_row.sql_text, true);
	IF p_hash_value IS NULL THEN
		open multi_stmt; -- caller asked for all statements
	ELSE
		open single_stmt(p_hash_value); -- retrieve only one statement
	END IF;
	LOOP
		IF p_hash_value IS NULL THEN
			FETCH multi_stmt INTO v_cur_hash_value, v_piece, v_sql_text;
			EXIT WHEN multi_stmt%NOTFOUND;
		ELSE
			FETCH single_stmt INTO v_cur_hash_value, v_piece, v_sql_text;
			EXIT WHEN single_stmt%NOTFOUND;
		END IF;
		IF v_piece=0 THEN -- new stmt starts
			IF  v_prev_hash_value IS NOT NULL THEN
				-- there was a previous statement which is now finished
				result_row.hash_value:=v_prev_hash_value;
				pipe row(result_row);
				-- trim the lob to lenght 0 for the next statement
				dbms_lob.trim(result_row.sql_text, 0);
				-- the current row holds piece 0 of the new statement - add it to CLOB
				dbms_lob.writeappend(result_row.sql_text, length(v_sql_text), v_sql_text);
			ELSE
				-- this is the first row ever
				result_row.hash_value:=v_cur_hash_value;
				dbms_lob.writeappend(result_row.sql_text, length(v_sql_text), v_sql_text);
			END IF;
		ELSE
			-- append the current piece to the CLOB
			result_row.hash_value:=v_cur_hash_value;
			dbms_lob.writeappend(result_row.sql_text, lengthb(v_sql_text), v_sql_text);
		END IF;
		v_prev_hash_value:=v_cur_hash_value;
	END LOOP;
	-- output last statement
	pipe row(result_row);
	dbms_lob.freetemporary(result_row.sql_text);
		IF p_hash_value IS NULL THEN
			CLOSE multi_stmt;
		ELSE
			CLOSE single_stmt;
		END IF;
	return;
END;
/

show errors

GRANT EXECUTE ON site_sys.sp_sqltext TO dba;

-- test by retrieving all statements
--select * from table(site_sys.sp_sqltext(null));
select * from table(site_sys.sp_sqltext(2805036170));
