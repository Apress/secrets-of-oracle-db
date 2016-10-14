-- successfully tested agains 10gR2 on Windows
-- works after startup nomount
variable type varchar2(10)
variable ident varchar2(10)
variable params varchar2(256)

begin
	--:type:='SBT_TAPE';
	:type:=NULL;
	:ident:='channel1';
	:params:=NULL;
end;
/

set serveroutput on

DECLARE
	v_devtype VARCHAR2(100);
	v_done BOOLEAN;
	v_maxPieces NUMBER;
	state binary_integer;
	v_type varchar2(128);
	name varchar2(128);
	bufsz binary_integer;
	bufcnt binary_integer;
	kbytes number;
	readrate binary_integer;
	parallel binary_integer;
	TYPE t_pieceName IS TABLE OF varchar2(255) INDEX BY binary_integer;
	v_pieceName t_pieceName;
BEGIN
	-- List the names of backup pieces. (see RMAN-08530: piece handle=%s in RMAN Log file - note:
	-- "RMAN-08530" is only printed when RMAN is called with switch msgno)
	-- ORA-19870: error reading backup piece if backup piece does not exist
	v_pieceName(1) := 'C:\TEMP\SYSTEM-05IU8L18.BKP';
	--v_pieceName(2) := 'C:\TEMP\DB-TEN-0OILGSH5-20070629';
	v_maxPieces:=v_pieceName.last;

	-- begin restore conversation for controlfiles and/or datafiles
	DBMS_BACKUP_RESTORE.restoreSetDataFile(check_logical=>false);

	-- request restore of controlfile; CFNAME controls where the controlfile gets restored
	-- if none of the backup pieces contain a controlfile, error ORA-19697: standby control file not found in backup set is thrown
	DBMS_BACKUP_RESTORE.restoreControlFileTo(cfname=>'c:\temp\control.ctl');
	-- request restore of data file(s)
	-- if requested file is not in backup piece, error ORA-19613: datafile 1 not found in backup set is thrown
	--dbms_backup_restore.RestoreDatafileTo(dfnumber => 1,toname => 'C:\TEMP\SYSTEM.DBF');
	--dbms_backup_restore.RestoreDatafileTo(dfnumber => 6,toname => 'C:\TEMP\LOB_TS02.DBF');

	-- Allocate a channel. (type=>null for DISK, type=>'SBT_TAPE' for media manager/tape)
	v_devtype := DBMS_BACKUP_RESTORE.deviceAllocate(type=>:type, ident=> :ident, params => :params);
	dbms_backup_restore.deviceStatus(
		state=>state,
		type=>v_type,
		name=>name,
		bufsz=>bufsz,
		bufcnt=>bufcnt,
		kbytes=>kbytes,
		readrate=>readrate,
		parallel=>parallel
	);
	dbms_output.put_line('device type '||v_type);
	dbms_output.put_line('device name '''||name||'''');
	dbms_output.put_line('bufsz '||bufsz);
	dbms_output.put_line('bufcnt '||bufcnt);
	dbms_output.put_line('kbytes '||kbytes);
	dbms_output.put_line('readrate '||readrate);
	dbms_output.put_line('parallel '||parallel);
	dbms_output.put_line('Start reading '||v_maxPieces||' backup pieces.');
	FOR i IN 1..v_maxPieces LOOP
		dbms_output.put_line('Reading backup piece '||v_pieceName(i));
		/*
		restore fails with these errors if files, that are not in the backup piece, are requested
		ORA-19615: some files not found in backup set
		ORA-19613: datafile 5 not found in backup set
		or when there is not controlfile in the backup piece
		ORA-19697: standby control file not found in backup set
		*/
		DBMS_BACKUP_RESTORE.restoreBackupPiece(handle=>v_pieceName(i), done=>v_done, params=>null);
		exit when v_done;
	END LOOP;
	-- might call FUNCTION fetchFileRestored to find out which files were restored

	-- Deallocate the channel...
	DBMS_BACKUP_RESTORE.deviceDeAllocate(:ident);
EXCEPTION
	WHEN OTHERS THEN
		-- RestoreCancel makes sure ORA-19590: conversation already active does not happen, when
		-- retrying in the same SQL*Plus session
		DBMS_BACKUP_RESTORE.RestoreCancel;
		DBMS_BACKUP_RESTORE.deviceDeAllocate(:ident);
	RAISE;
END;
/
