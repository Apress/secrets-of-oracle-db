-- $Header: /cygdrive/c/home/ndebes/it/sql/RCS/dbms_job_metadata.sql,v 1.4 2008/01/01 23:12:01 ndebes Exp ndebes $
CREATE TABLE site_sys.job_logging (
	job number,
	next_date date,
	broken varchar2(1),
	additional_info varchar2(4000)
);
variable job number
begin
	dbms_job.submit(
		job=>:job, 
		what=> 'DECLARE
	v_broken varchar2(1);
	v_additional_info varchar2(4000);
	v_job number:=job;
	v_next_date date:=next_date;
BEGIN
	-- next_date may be overridden
	-- next_date:=to_date(''1.1.3000'',''dd.mm.yyyy'');
	-- DBMS_JOB metadata variable broken is set to false in the surrounding PL/SQL block
	-- Must query ALL_JOBS to get current broken value of this job
	SELECT broken INTO v_broken FROM all_jobs WHERE job=v_job;
	INSERT INTO site_sys.job_logging(job, next_date, broken) 
	VALUES (v_job, v_next_date, v_broken);
	commit;
	BEGIN
		statspack.snap;
		-- DBMS_JOB automatically reenables a job, if it is currently broken,
		-- but a manual run with DBMS_JOB.RUN succeeds
	EXCEPTION WHEN OTHERS THEN 
		broken:=true;
		-- next_date may be overridden
		-- next_date:=to_date(''1.1.3000'',''dd.mm.yyyy'');
		v_additional_info:=SQLERRM;
		UPDATE site_sys.job_logging 
		SET additional_info=v_additional_info
		WHERE job=job
		AND next_date=v_next_date;
		commit;
		-- When re-raising exception, cannot mark job as broken, since DBMS_JOB code
		-- which checks variable broken is not executed due to the exception
		-- RAISE; 
	END;
END;',
		next_date=>sysdate,
		interval=>'sysdate+1/24'
	);
	commit;
end;
/
exec dbms_job.run(:job)
alter session set nls_date_format='dd-Mon-yyyy hh24:mi:ss';
SET NULL <NULL>
col job format 99
col additional_info format a40 word_wrapped
col broken format a6
col past_broken_value format a17
set pages 99
SELECT j.job, j.broken, l.broken AS past_broken_value, l.next_date, additional_info
FROM dba_jobs j, site_sys.job_logging l
WHERE j.job=:job
AND j.job=l.job
ORDER BY l.next_date;



SELECT * FROM site_sys.job_logging WHERE job=:job;

SELECT job, what, next_date, broken FROM dba_jobs where job=:job;

exec dbms_job.next_date(:job, sysdate+3/1440)

SQL> SELECT sysdate, next_date FROM all_jobs WHERE job=:job;

NEXT_DATE
--------------------
02-Jan-2008 00:22:51

