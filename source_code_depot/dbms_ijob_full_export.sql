col what format a45
SELECT job, what FROM dba_jobs;
set heading off
set feedback off
set linesize 2000
col submit_call format a2000
col instance_call format a200
set trimout on
set trimspool on
variable job number
variable submit_call varchar2(4000)
variable instance_call varchar2(4000)
exec :job:=&job_number;
begin
	dbms_ijob.full_export(:job, :submit_call, :instance_call);
end;
/
print submit_call
print instance_call
select 'commit;' from dual;
