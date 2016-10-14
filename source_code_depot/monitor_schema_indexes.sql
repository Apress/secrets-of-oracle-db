@@view_index_usage
-- enable index usage monitoring in a schema
CREATE OR REPLACE FUNCTION site_sys.monitor_schema_indexes (
	ownname VARCHAR2 DEFAULT NULL,
	failed_counter out number,
	monitoring BOOLEAN DEFAULT TRUE

) RETURN INTEGER AUTHID CURRENT_USER 
AS
	resource_busy exception;
	PRAGMA exception_init(resource_busy, -54);
	counter integer:=0;
	schema_name varchar2(30);
	stmt varchar2(256);
	cursor not_monitored(p_schema_name varchar2) is 
		SELECT index_name 
		FROM all_indexes i, all_tables t
		where i.owner=p_schema_name
		and i.table_name=t.table_name
		and i.table_owner=t.owner
		-- cannot be used on index of type IOT ORA-25176: storage specification not permitted for primary key
		and t.iot_type IS NULL
		and index_type != 'DOMAIN'
		MINUS
		SELECT index_name 
		FROM site_sys.index_usage 
		WHERE owner=p_schema_name 
		AND monitoring='YES';
	cursor monitored(p_schema_name varchar2) is
	SELECT index_name
	FROM site_sys.index_usage
	WHERE owner=p_schema_name
	and monitoring='YES';
begin
	schema_name:=nvl(ownname,user);
	failed_counter:=0;
	IF monitoring = TRUE THEN
		for record in not_monitored(schema_name) LOOP
			BEGIN
				stmt:='ALTER INDEX '||schema_name||'."'||record.index_name||'" monitoring usage';
				execute immediate stmt;
				counter:=counter+1;
			EXCEPTION WHEN resource_busy THEN
				failed_counter:=failed_counter+1;
			END;
		END LOOP;
	ELSE
		for record in monitored(schema_name) LOOP
			BEGIN
				stmt:='ALTER INDEX '||schema_name||'."'||record.index_name||'" NOMONITORING USAGE';
				execute immediate stmt;
				counter:=counter+1;
			EXCEPTION WHEN resource_busy THEN
				failed_counter:=failed_counter+1;
			END;
		END LOOP;
	END IF;
	return counter;
	/*
EXCEPTION WHEN OTHERS THEN
				raise_application_error(-20000, 'Error in procedure site_sys.monitor_schema_indexes executing '''
				|| stmt||'''', TRUE);
*/
end;
/
show errors
GRANT execute ON site_sys.monitor_schema_indexes TO PUBLIC;
