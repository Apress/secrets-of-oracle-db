exec dbms_aqadm.create_queue_table('post_office_queue_table', 'raw');
exec dbms_aqadm.create_queue('caught_in_slow_q_again', 'post_office_queue_table');
exec dbms_aqadm.start_queue('caught_in_slow_q_again');
ALTER SESSION SET SQL_TRACE=TRUE;


DECLARE
	dequeue_options dbms_aq.dequeue_options_t;
	message_properties dbms_aq.message_properties_t;
	payload blob;
	msgid raw(16);
BEGIN
	dequeue_options.wait:=dbms_aq.no_wait; -- default is to patiently wait forever
	DBMS_AQ.DEQUEUE (
		queue_name => 'caught_in_slow_q_again',
		dequeue_options => dequeue_options,
		message_properties => message_properties,
		payload => payload,
		msgid => msgid);
END;
/
-- requires GRANT EXECUTE ON dbms_aq TO <user>;
create or replace function deq(wait_time number default null) return varchar2
as
	dequeue_options dbms_aq.dequeue_options_t;
	message_properties dbms_aq.message_properties_t;
	payload blob;
	msgid raw(16);
BEGIN
	if wait_time > 0 then
		dequeue_options.wait:=wait_time;
	end if;
	DBMS_AQ.DEQUEUE (
		queue_name => 'caught_in_slow_q_again',
		dequeue_options => dequeue_options,
		message_properties => message_properties,
		payload => payload,
		msgid => msgid);
	return rawtohex(msgid);
END;
/

set autoprint on
variable result varchar2(80)
exec :result:=deq(1);
-- passing null means wait for next message without timout
-- exec :result:=deq;
