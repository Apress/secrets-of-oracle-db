-- $Header$
variable type varchar2(10)
variable ident varchar2(10)
variable piece1 varchar2(513)
begin
        :type:='SBT_TAPE';
        :ident:='channel1';
	:piece1:='CF-DB-NINE-20071010-vsiu61og';
end;
/
set serveroutput on
DECLARE
	v_devtype   VARCHAR2(100);
	v_done      BOOLEAN;
	v_maxPieces NUMBER;
	TYPE t_pieceName IS TABLE OF varchar2(513) INDEX BY binary_integer;
	v_piece_name_tab t_pieceName;
BEGIN
	-- Define the backup pieces... (names from the RMAN Log file or TSM repository)
	v_piece_name_tab(1) := :piece1;
	--v_piece_name_tab(2) := '<backup piece name 2>';
	v_maxPieces    := 1;
/*
FUNCTION DEVICEALLOCATE RETURNS VARCHAR2
 Argument Name                  Type                    In/Out Default?
 ------------------------------ ----------------------- ------ --------
 TYPE                           VARCHAR2                IN     DEFAULT
 NAME                           VARCHAR2                IN     DEFAULT
 IDENT                          VARCHAR2                IN     DEFAULT
 NOIO                           BOOLEAN                 IN     DEFAULT
 PARAMS                         VARCHAR2                IN     DEFAULT
*/
	-- Allocate a channel... (Use type=>null for DISK, type=>'sbt_tape' for TAPE)
	v_devtype := DBMS_BACKUP_RESTORE.deviceAllocate(
        	type=>:type,
        	ident=> :ident,
        	params => 'ENV=(TDPO_OPTFILE=/usr/tivoli/tsm/client/oracle/bin64/tdpo.opt)'
	);
  	dbms_output.put_line('device type '||v_devtype);
	-- begin restore conversation
	DBMS_BACKUP_RESTORE.restoreSetDataFile(check_logical=>false);
	-- set restore location with CFNAME parameter
	DBMS_BACKUP_RESTORE.restoreControlFileTo(cfname=>'/tmp/control.ctl');
	FOR i IN 1..v_maxPieces LOOP
		dbms_output.put_line('Restoring from piece '||v_piece_name_tab(i));
		DBMS_BACKUP_RESTORE.restoreBackupPiece(handle=>v_piece_name_tab(i), done=>v_done, params=>null);
		exit when v_done;
	END LOOP;
	-- Deallocate the channel...
	DBMS_BACKUP_RESTORE.deviceDeAllocate(:ident);
	EXCEPTION WHEN OTHERS THEN
		DBMS_BACKUP_RESTORE.deviceDeAllocate(:ident);
	RAISE;
END;
/
