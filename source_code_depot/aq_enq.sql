SET SERVEROUTPUT ON
DECLARE
	enqueue_options dbms_aq.enqueue_options_t;
	message_properties dbms_aq.message_properties_t;
	payload blob;
	msg raw(64);
	msgid raw(16);
BEGIN
	dbms_lob.createtemporary(payload, true);
	msg:=utl_raw.cast_to_raw('message in a bottle');
	dbms_lob.writeappend(payload, utl_raw.length(msg), msg);
	DBMS_AQ.ENQUEUE (
		queue_name => 'caught_in_slow_q_again',
		enqueue_options => enqueue_options,
		message_properties => message_properties,
		payload => payload,
		msgid => msgid);
	dbms_output.put_line(rawtohex(msgid));
END;
/
COMMIT;
SELECT tab.msgid, tab.state
FROM "NDEBES"."POST_OFFICE_QUEUE_TABLE" tab  
WHERE q_name='CAUGHT_IN_SLOW_Q_AGAIN';


