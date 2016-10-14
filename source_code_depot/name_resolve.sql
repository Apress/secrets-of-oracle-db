set feedback off
variable name varchar2(30)
variable context number
variable schema varchar2(30)
variable part1 varchar2(30)
variable part2 varchar2(30)
variable dblink varchar2(30)
variable part1_type number
variable object_number number
whenever sqlerror exit failure

set autoprint on
exec :name:='&1'

declare
	context number;
	max_context constant number:=7;
	incompatible_with_context EXCEPTION;
	pragma exception_init(incompatible_with_context, -4047);
	object_does_not_exist EXCEPTION;
	pragma exception_init(object_does_not_exist, -6564);
begin
	for context in 1..max_context loop
		begin
		:context:=context;
		DBMS_UTILITY.NAME_RESOLVE (
		name => :name,
		context => :context,
-- 10g doc says: context Must be an integer between 0 and 8.
-- but in 9i and 10g context 0 or 8 gives:
-- ORA-20005: ORU-10034: context argument must be 1 or 2 or 3 or 4 or 5 or 6 or 7
-- context 1: for packages, procedures, functions
-- context 2: works for schema.table, schema.synonym, queue, view, table.partition resolved to schema.table
-- context 7: works for TYPEs
-- apparently index names, table partitions cannot be resolved
		schema => :schema,
		part1 => :part1,
		part2 => :part2,
		dblink => :dblink,
		part1_type => :part1_type,
		object_number => :object_number);

		-- if no exception is raised, the object is found and control can be
		-- returned to the caller
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
print context
col object_name format a30
col owner format a12

-- note: NVL2 does not work in 9iR2 PL/SQL due to PLS-00201: identifier 'NVL2' must be declared
-- :name || ' is a ' || 
SELECT 
-- resolved_name
'"' || :schema|| '"' || nvl2(:part1,'."'||:part1 || '"', null)|| 
nvl2(:part2,'."'||:part2 || '"',NULL) ||
nvl2(:dblink,'@"'||:dblink || '"' ,NULL) ||
' is a ' ||
-- translate part1_type to object type
decode(:part1_type, 0, 'object at a remote database', 2, 'table', 4, 'view', 6, 'sequence', 7, 'procedure', 8, 'function', 9, 'package', 12, 'trigger', 13, 'type') || 
' (PART1_TYPE=' || :part1_type || ', OBJECT_NUMBER=' ||
:object_number || ')'
AS detailed_info
FROM dual;

SELECT owner, object_name, object_type FROM dba_objects WHERE object_id=:object_number;
exit
