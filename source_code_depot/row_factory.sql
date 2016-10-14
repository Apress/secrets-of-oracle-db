CREATE OR REPLACE TYPE row_nr_type AS OBJECT (row_nr number);
/
show errors

CREATE OR REPLACE TYPE row_nr_type_tab AS TABLE OF row_nr_type;
/
show errors

CREATE OR REPLACE FUNCTION row_factory(first_nr number, last_nr number)
RETURN row_nr_type_tab PIPELINED
AS
	row_nr row_nr_type:=NEW row_nr_type(0);
BEGIN
	FOR i IN first_nr .. last_nr LOOP
		row_nr.row_nr:=i;
		PIPE ROW(row_nr);
	END LOOP;
	return;
END;
/
show errors
SELECT * FROM TABLE(row_factory(1,10));

CREATE TABLE random_strings AS
SELECT dbms_random.string('a', 128) AS random_string FROM TABLE(row_factory(1,1000000)) NOLOGGING;

