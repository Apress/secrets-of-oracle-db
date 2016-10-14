begin
	dbms_stats.set_system_stats('sreadtim', 4);
	dbms_stats.set_system_stats('mreadtim', 10 );
	dbms_stats.set_system_stats('cpuspeed', 839);
	dbms_stats.set_system_stats('mbrc', 14);
	dbms_stats.set_system_stats('maxthr', 8 * 1048576);
end;
/

-- exec dbms_stats.import_system_stats('system_stats', 'sysstat_29nov07_13h25', 'site_sys')
