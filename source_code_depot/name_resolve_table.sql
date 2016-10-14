-- $Header: /cygdrive/c/home/ndebes/it/sql/RCS/name_resolve_table.sql,v 1.1 2007/12/13 17:25:25 ndebes Exp ndebes $
variable name varchar2(100)
variable context number
variable schema varchar2(30)
variable part1 varchar2(30)
variable part2 varchar2(30)
variable dblink varchar2(30)
variable part1_type number
variable object_number number

begin
	:context:=2; -- 1: package, 2: table
	:name:=' "SYSTEM" . Product_User_Profile @ db_link'; -- name to resolve
	:name:=' "SYSTEM" . Product_User_Profile '; -- name to resolve
	DBMS_UTILITY.NAME_RESOLVE (
		name => :name,
		context => :context,
		schema => :schema,
		part1 => :part1,
		part2 => :part2,
		dblink => :dblink,
		part1_type => :part1_type,
		object_number => :object_number
	);
end;
/
set linesize 150
col detailed_info format a80 word_wrapped
col owner format a8
col object_name format a30
SELECT 
-- resolved_name
'"' || :schema|| '"' || nvl2(:part1,'."'||:part1 || '"', null)|| 
nvl2(:part2,'."'||:part2 || '"',NULL) ||
nvl2(:dblink,'@"'||:dblink || '"' ,NULL)
|| ' is ' || 
-- translate part1_type to object type
decode(:part1_type, 0, 'an object at a remote database', 2, 'a table', 4, 'a view', 6, 'a sequence', 7, 'a procedure', 8, 'a function', 9, 'a package', 12, 'a trigger', 13, 'a type') || 
' (PART1_TYPE=' || :part1_type || ', OBJECT_NUMBER=' ||
:object_number || ')'
AS detailed_info
FROM dual;
SELECT owner, object_name, object_type, status, created 
FROM all_objects 
WHERE object_id=:object_number;
