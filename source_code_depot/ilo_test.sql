alter session set tracefile_identifier='ilo_test';
/*
pre ILO 2.0
-- default nesting level is 0. Nothing happens at nesting level 0 (new in 1.4)
exec hotsos_ilo_task.set_nesting_level(100)
exec hotsos_ilo_task.set_config(trace=>true,write_wall_time=>false)
*/
-- ILO 2.0: must be called to switch on tracing
exec hotsos_ilo_timer.set_mark_all_tasks_interesting(true, true)
select 'no task' from dual;
begin 
	hotsos_ilo_task.begin_task(
		module=>'test',
		action=>'first'
	);
end;
/
select 'test-first' from dual;
begin 
	hotsos_ilo_task.begin_task(
		module=>'test',
		action=>'second',
		client_id=>'ilo_test'
	);
end;
/
select 'test-second' from dual;
exec hotsos_ilo_task.end_task
select 'test-first again' from dual;
exec hotsos_ilo_task.end_task

oradebug setmypid
oradebug tracefile_name
