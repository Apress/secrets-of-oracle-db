-- site_sys needs quota on default tablespace
define installation_schema=site_sys
set feedback off
variable name varchar2(128)
variable schema varchar2(30)
variable part1 varchar2(30)
variable part2 varchar2(30)
variable dblink varchar2(30)
variable part1_type number
variable object_number number
variable name_resolved varchar2(128)

--set termout off
-- database objects for testing
create cluster &installation_schema..myclu (n number);
create table &installation_schema..myclutab (n number) cluster &installation_schema..myclu(n);
create index &installation_schema..mycluind on cluster &installation_schema..myclu;
create table &installation_schema..mytab(n number, b blob);
create index &installation_schema..myind(n) on &installation_schema..mytab;
create view &installation_schema..myview as select * from &installation_schema..mytab;
create synonym &installation_schema..mysynonym for &installation_schema..myview;
create table &installation_schema..parttab (n number) partition by range(n) (partition p1 values less than (maxvalue));
create sequence &installation_schema..myseq;
-- directory cannot be prefixed with schema
create directory mydir as '/';
create or replace trigger &installation_schema..mytrig before insert on &installation_schema..mytab for each row
begin
	select &installation_schema..myseq.nextval into :new.n from dual;
end;
/
create type &installation_schema..mytype as object (n number);
/
create function &installation_schema..myfunc return number as begin null; end;
/
exec dbms_aqadm.create_queue_table('&installation_schema..myqueuetab', 'raw');
exec dbms_aqadm.create_queue('&installation_schema..myqueue', '&installation_schema..myqueuetab');
set termout on

whenever sqlerror exit failure

set serveroutput on

set feedback on
create or replace procedure &installation_schema..NAME_RESOLVE (
name IN VARCHAR2,
schema OUT VARCHAR2,
part1 OUT VARCHAR2,
part2 OUT VARCHAR2,
dblink OUT VARCHAR2,
part1_type OUT NUMBER, /* 
2: table (undocumented in 10gR2) ok
4: view ok
6: sequence (undocumented in 10gR2) ok
7: procedure ok
8: function ok
9: package ok
12: trigger (undocumented in 10gR2) ok
13: type (undocumented in 10gR2) ok
*/
object_number OUT NUMBER,
name_resolved OUT VARCHAR2) AUTHID CURRENT_USER
as
	part1_tmp VARCHAR2(30);
	part2_tmp VARCHAR2(30);
	dblink_tmp VARCHAR2(30);
	context number;
	max_context constant number:=7;
	incompatible_with_context EXCEPTION;
	pragma exception_init(incompatible_with_context, -4047);
	object_does_not_exist EXCEPTION;
	pragma exception_init(object_does_not_exist, -6564);
begin
	for context in 1..max_context loop
		begin
		DBMS_UTILITY.NAME_RESOLVE (
		name => name,
		context => context,
-- 10g doc says: context Must be an integer between 0 and 8.
-- but in 9i and 10g context 0 or 8 gives:
-- ORA-20005: ORU-10034: context argument must be 1 or 2 or 3 or 4 or 5 or 6 or 7
-- context 1: for PL/SQL packages, 
--	package.procedure (resolved to schema.package.procedure correctness of procedure not checked), 
--	package.function (resolved to schema.package.function correctness of function not checked), 
--	procedures, functions
-- context 2: works for table, 
--	table.column (resolved to schema.table, correctness of column_name not checked),
--	table.partition (resolved to schema.table), sequence, synonym, view
-- context 3: works for TRIGGERs
-- context 7: works for TYPEs
-- clusters, database links, directories, indexes, LOB column names, queues, rule names, rule sets cannot be resolved
		schema => schema,
		part1 => part1,
		part2 => part2,
		dblink => dblink,
		part1_type => part1_type,
		object_number => object_number);

		-- if no exception is raised, the object is found and control can be
		-- returned to the caller
		-- note: NVL2 does not work in 9iR2 and 10g PL/SQL due to PLS-00201: identifier 'NVL2' must be declared
		IF part1 IS NOT NULL THEN
			part1_tmp:='."'||part1 || '"';
		END IF;
		-- for packages and tables part2 ist not checked for correctness, e.g. resolving dbms_utility.x
		-- gives part2='X' although there is no procedure or function x in dbms_utility
		-- to avoid returning something that does not exist, part2 is cleared for packages
		-- and tables
		IF part2 IS NOT NULL THEN
			IF part1_type=9 or part1_type=2 /* package or table */ THEN
				part2_tmp:=NULL;
			ELSE
				part2_tmp:='."'||part2 || '"';
			END IF;
		END IF;

		IF dblink IS NOT NULL THEN
			dblink_tmp:='@"'||dblink || '"';
		END IF;
		name_resolved:='"' || schema || '"' || part1_tmp ||  part2_tmp || dblink_tmp;
		return;
		exception 
			when incompatible_with_context or object_does_not_exist then
			begin
				if context = max_context then
				 	-- reraise exception when all contexts have been tried
					-- reraising preserves the object name in the error message, 
					-- which cannot be passed in a raise statement with an argument
					raise;
				else
					null;
				end if;
			end;
		end;
	end loop;
end;
/
show errors
GRANT EXECUTE ON &installation_schema..NAME_RESOLVE TO PUBLIC;

set serveroutput on
exec :name:='&1'
begin
	&installation_schema..NAME_RESOLVE (
		name => :name,
		schema => :schema,
		part1 => :part1,
		part2 => :part2,
		dblink => :dblink,
		part1_type => :part1_type,
		object_number => :object_number,
		name_resolved => :name_resolved
	);
end;
/
set linesize 100
set feedback off
col detailed_info format a80 word_wrapped
col object_name format a30
SELECT 
-- resolved_name
:name_resolved || ' is a ' || 
-- translate part1_type to object type
decode(:part1_type, 0, 'object at a remote database', 2, 'table', 4, 'view', 6, 'sequence', 7, 'procedure', 8, 'function', 9, 'package', 12, 'trigger', 13, 'type') || 
' (PART1_TYPE=' || :part1_type || ', OBJECT_NUMBER=' ||
:object_number || ')' 
AS detailed_info
FROM dual;

SELECT owner, object_name, object_type FROM dba_objects WHERE object_id=:object_number;
exit
