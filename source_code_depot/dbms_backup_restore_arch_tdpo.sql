-- $Header$
variable type varchar2(10)
variable ident varchar2(10)
variable piece1 varchar2(513)
variable piece2 varchar2(513)
begin
        :type:='SBT_TAPE';
        :ident:='channel1';
	:piece1:='DB-NINE-ARCHLOG-v8iu1ekh-DateYYYYMMDD-20071009';
	:piece2:='DB-NINE-ARCHLOG-vliu42v9-DateYYYYMMDD-20071010';
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
	--v_piece_name_tab(2) := :piece2;
	v_maxPieces    := 1;
	-- Allocate a channel... (Use type=>null for DISK, type=>'sbt_tape' for TAPE)
	v_devtype := DBMS_BACKUP_RESTORE.deviceAllocate(
        	type=>:type,
        	ident=> :ident,
        	params => 'ENV=(TDPO_OPTFILE=/usr/tivoli/tsm/client/oracle/bin64/tdpo.opt)'
	);
  	dbms_output.put_line('device type '||v_devtype);
	-- set restore location with DESTINATION parameter
	dbms_backup_restore.RestoreSetArchivedLog(destination=>'/tmp');
	-- begin restore conversation
	dbms_backup_restore.RestoreArchivedLog(thread=>1, sequence=>1818);
	-- if more than one archived log in piece, add sequence number
	-- dbms_backup_restore.RestoreArchivedLog(thread=>1, sequence=>1819);
	-- must restore archived logs from one backup set at a time, otherwise will get
	-- ORA-19614: archivelog thread 1 sequence 1819 not found in backup set
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
