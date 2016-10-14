#!/usr/bin/env perl
use DBI;
my $dbh=DBI->connect('dbi:Oracle:','/','') or die "Failed to connect.\n";
my $sth=$dbh->prepare("SELECT user FROM dual");
$sth->execute;
my @row=$sth->fetchrow_array;
printf "Connected as user %s.\n", $row[0];
