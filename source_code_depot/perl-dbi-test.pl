#!/usr/bin/env perl
# RCS: $Header: /cygdrive/c/home/ndebes/it/perl/RCS/perl-dbi-test.pl,v 1.1 2007/01/26 16:07:13 ndebes Exp ndebes $
# Perl DBI/DBD Oracle Example

use strict;
use DBI;

print "Username: \n";
my $user = <STDIN>;
chomp $user;
print "Password: \n";
my $passwd = <STDIN>;
chomp $passwd;
print "Net Service Name (optional, if Oracle instance runs locally and ORACLE_SID is set): \n";
my $net_service_name = <STDIN>;    ## Oracle Net servicename from tnsnames.ora or other name resulution method
chomp $net_service_name;

if ($net_service_name) {
	print "Trying to connect to $user/$passwd\@$net_service_name\n";
}
else {
	print "Trying to connect to $user/$passwd\n";
}

# Connect to the database and return a database handle
my $dbh = DBI->connect("dbi:Oracle:${net_service_name}", $user, $passwd)
	or die "Connect failed: $DBI::errstr";

my $sth = $dbh->prepare("SELECT user FROM dual"); # PARSE
$sth->execute(); # EXECUTE
my @row = $sth->fetchrow_array(); # FETCH
printf ("Connected as user %s\n", $row[0]);
$sth->finish; 
$dbh->disconnect; # disconnect from Oracle instance

=pod

#### Prepare and Execute a SQL Statement Handle
my $sth = $dbh->prepare("SELECT owner,table_name,num_rows FROM all_tables");

$sth->execute();

print("Owner\tTableName\tNumRows\n");
print("-----\t---------\t-------\n");
while(my @row = $sth->fetchrow_array()) {
        print("$row[0]\t$row[1]\t$row[2]\n");
}
printf "%d row(s) SELECTed\n", $sth->rows;
$sth->finish;
print("Select Done.\n");

#### Disconnect
if($dbh->disconnect){
        print("Disconnected.\n");
} else {
        print("Failed to disconnect!\n");
}

=cut
