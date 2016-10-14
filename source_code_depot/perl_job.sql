exec dbms_scheduler.drop_job('perl_job');
exec dbms_scheduler.drop_program('perl_program');
-- adjust PATH according to your installation. PATH must include the path to perl and to test.pl
begin
	dbms_scheduler.create_program(
	program_name=>'perl_program',
	program_type=>'EXECUTABLE',
	program_action=> '/usr/bin/env',
	number_of_arguments=>2,
	enabled=>false
	);
	dbms_scheduler.define_program_argument(
		program_name=>'perl_program',
		argument_position=>1,
		argument_name=>'env',
		argument_type=>'VARCHAR2',
		default_value=>'PATH=/opt/oracle/product/db10.2/perl/bin:/home/oracle'
	);
	dbms_scheduler.define_program_argument(
		program_name=>'perl_program',
		argument_position=>2,
		argument_name=>'script',
		argument_type=>'VARCHAR2',
		default_value=>'test.pl'
	);
	dbms_scheduler.enable('perl_program');
	dbms_scheduler.create_job(
		job_name=>'perl_job',
		program_name=>'perl_program',
		enabled=>false,
		auto_drop=>false
	);
end;
/
exec dbms_scheduler.run_job('perl_job')
SELECT status, additional_info 
FROM dba_scheduler_job_run_details 
WHERE log_id=(SELECT max(log_id) FROM dba_scheduler_job_run_details);
