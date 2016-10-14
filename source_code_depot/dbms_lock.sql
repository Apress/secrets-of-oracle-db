variable lockhandle varchar2(128)
BEGIN
	-- get a lock handle for the lockname that was agreed upon
	-- make sure you choose a unique name, such that other vendors' applications
	-- won't accidentally interfere with your locks
	DBMS_LOCK.ALLOCATE_UNIQUE(
		lockname => 'MYAPP_MUTEX1', 
		lockhandle => :lockhandle
	);
END;
/
print lockhandle

SELECT * FROM sys.dbms_lock_allocated /* no public synonym  */;
variable result number
BEGIN
	-- request the lock with the handle obtained above in exclusive mode
	-- the first session running this code will succeed
	:result:=DBMS_LOCK.REQUEST(
		lockhandle => :lockhandle,
		lockmode => DBMS_LOCK.X_MODE,
		timeout => 0,
		release_on_commit => TRUE /* default is false */
	);
END;
/
SELECT decode(:result,0,'Success',
	1,'Timeout',
	2,'Deadlock',
	3,'Parameter error',
	4,'Already own lock specified by id or lockhandle',
	5,'Illegal lock handle') Result
FROM dual;

SELECT p1, p1text, p2, p2text, wait_class, seconds_in_wait, state 
FROM v$session_wait 
WHERE event='enq: UL - contention';


SELECT name
FROM sys.dbms_lock_allocated la, v$session_wait sw
WHERE sw.event='enq: UL - contention'
AND la.lockid=sw.p2;

