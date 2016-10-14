#!/usr/bin/env perl

=pod

create table customer(
  id number(*,0) not null, 
  name varchar2(10), 
  phone varchar2(30)
);
create sequence customer_id_seq nocache;
create or replace trigger ins_customer before insert on customer for each row
begin
  SELECT customer_id_seq.nextval INTO :new.id FROM dual;
end;
/
variable id number
INSERT INTO customer(name, phone) VALUES ('&name', '&phone') RETURNING id INTO :id;
print id

CLEANUP
=======
drop table customer;
drop sequence customer_id_seq;

SELECT n.name, s.value 
FROM v$sesstat s, v$statname n, v$session se
WHERE s.statistic#=n.statistic#
AND n.name IN ('db block gets', 'consistent gets')
AND s.sid=se.sid
AND se.program='perl.exe';

=cut

if ( ! defined $ARGV[0] ) {
  printf "Usage: $0 iterations\n";
  exit;
}

# declare and initialize variables
my ($id, $name, $phone, $sth)=(undef, "Hans", "089/4711", undef);

use File::Basename;
use DBI; # import DBI module
#print "DBI Version: $DBI::VERSION\n"; # DBI version is available after use DBI
use strict; # variables must be declared with my before use
my $dbh = DBI->connect(undef, undef, undef, 
  # set recommended values for attributes
  {ora_module_name => basename($0),RaiseError=>1, PrintError=>0,AutoCommit => 0}) 
  or die "Connect failed: $DBI::errstr";
# DBD::Oracle version is available after connect
#print "DBD::Oracle Version: $DBD::Oracle::VERSION\n";

# start eval block for catching exceptions thrown by statements inside the block
eval {
  # tracing facility: if environment variable SQL_TRACE_LEVEL is set, 
  # enable SQL trace at that level
  my $trc_ident=basename($0); # remove path component from $0, if present

	print "Hit return to continue\n";
	my $answer=<STDIN>;
  if ( defined($ENV{SQL_TRACE_LEVEL})) {
          $dbh->do("alter session set tracefile_identifier='$trc_ident'");
          $dbh->do("alter session set events '10046 trace name context forever, level $ENV{SQL_TRACE_LEVEL}'");
  }

=for commentary

  # parse an anonymous PL/SQL block for retrieving the Oracle DBMS version 
  # and compatibility # as well as the database and instance names
  # V$ views are not used, since they may be accessed by privileged users only
  # quoting with q{<SQL or PL/SQL statements>} is used, since 
  # it avoids trouble with quotes (", ')
  $sth = $dbh->prepare(q{
  begin
          dbms_utility.db_version(:version, :compatibility);
          :result:=dbms_utility.get_parameter_value('db_name',:intval, :db_name);
          :result:=dbms_utility.get_parameter_value('instance_name', :intval, 
      :instance_name);
  end;
  });
  my ($version, $compatibility, $db_name, $instance_name, $result, $intval);
  $sth->bind_param_inout(":version", \$version, 64);
  $sth->bind_param_inout(":compatibility", \$compatibility, 64);
  $sth->bind_param_inout(":db_name", \$db_name, 9);
  $sth->bind_param_inout(":instance_name", \$instance_name, 16);
  $sth->bind_param_inout(":intval", \$intval, 2);
  $sth->bind_param_inout(":result", \$result, 1);
  $sth->execute;

  $sth = $dbh->prepare(q{SELECT userenv('sid'), 
    to_char(sysdate, 'Day, dd. Month yyyy hh24:mi:ss "(week" IW")"') FROM dual});
  $sth->execute;
  my ($sid, $date_time);
  # pass reference to variables which correspond to columns in 
  # SELECT from left to right
  $sth->bind_columns(\$sid, \$date_time);
  my @row = $sth->fetchrow_array;

  printf "Connected to Oracle instance %s, release %s (compatible=%s)", 
  $instance_name, $version, $compatibility;
  printf "; Database %s\n", $db_name;
  # due to bind_columns, may now use meaningful variable names instead of $row[0], etc.
  printf "Session %d on %s\n", $sid, $date_time;

=cut

  $sth = $dbh->prepare("INSERT INTO customer(name, phone) VALUES (:name, :phone) 
        RETURNING id INTO :id", { ora_check_sql => 0 });
  # loop, number of iterations is in command line argument
  for (my $i=0; $i < $ARGV[0]; $i++) {
    # bind_param_inout is for receiving values from the DBMS
    $sth->bind_param_inout(":id", \$id, 38);
    # bind_param is for sending bind variable values to the DBMS
    # assign value to bind variable (placeholder :name)
    $sth->bind_param(":name", $name);
    # assign value to bind variable "phone"
    $sth->bind_param(":phone", $phone);
    # execute the INSERT statement
    $sth->execute();
    #printf "New customer with id %d inserted.\n", $id;
  }
};
# check for exceptions
if ($@) {
  printf STDERR "ROLLBACK due to Oracle error %d: %s\n", $dbh->err, $@;
  # ROLLBACK any previous INSERTs
  $dbh->rollback;
  exit;
} else {
  # commit once at end
  $dbh->commit;
}
$sth->finish; # close statement handle
print "Hit return to continue\n";
my $answer=<STDIN>;
$dbh->disconnect; # disconnect from Oracle instance
