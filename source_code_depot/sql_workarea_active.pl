#!/usr/bin/env perl

use DBI;

$dbh = DBI->connect(undef, undef, undef, { RaiseError => 1, AutoCommit => 0 } ) || die "Database connection not made: $DBI::errstr";

$sth = $dbh->prepare(q{SELECT sid, to_char(sysdate,'mi:ss') time, round(work_area_size/1048576, 1) work_area_size_mb, 
round(max_mem_used/1048576, 1) max_mem_used_mb, number_passes, nvl(tempseg_size/1048576, 0) tempseg_size_mb
FROM v$sql_workarea_active 
ORDER BY sid
});
my $format="%5s %5s %14s %12s %6s %12s\n";
printf($format, "SID", "TIME", "WORK_AREA_SIZE", "MAX_MEM_USED", "PASSES", "TEMPSEG_SIZE");
for (;1!=2;) {
	$sth->execute;
	while ( @row = $sth->fetchrow_array ) {
     		printf($format, $row[0], $row[1], $row[2], $row[3], $row[4], $row[5]);
	}
	sleep 1;
}
$dbh->disconnect;

