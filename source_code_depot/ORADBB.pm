# $Header: /cygdrive/c/home/ndebes/it/perl/RCS/ORADBB.pm,v 2.6 2007/08/08 08:37:15 ndebes Exp ndebes $
# ORADBB - package for implementing an Oracle database browser.
# Executes arbitrary statements through Perl DBI against an Oracle DBMS instance

=head1 ORADBB - Oracle database interface based on Perl DBI and DBD::Oracle

ORADBB provides an API that simplifies the development of Perl/DBI applications against 
Oracle Databases. ORADBB uses features that apply specifically to the Oracle Database Management System (DBMS) such as
named binding of placeholders (bind variables) in SQL statements (column=:bindvar, instead of column=?) and support for
connections with SYSDBA or SYSOPER privilege. Thus ORADBB will not work against other DBMSs.

Features include:

=over

=item * retrieving an Oracle connect string from the command line (L<build_connect_string|Subroutine build_connect_string>)

=item * parsing an Oracle connect string, i.e. a string that contains username, password, TNS servicename and optionally one of the privileges NORMAL, SYSOPER or SYSDBA (L<parse_connect_string|Subroutine parse_connect_string>)

=item * connecting to an Oracle DBMS instance (L<dbms_connect|Subroutine dbms_connect>)

=item * running an arbitrary SQL statement against an Oracle instance (L<process_stmt|Subroutine process_stmt>)

=item * printing the results of an arbitrary SQL statement on an alphanumeric terminal (L<print_stmt|Subroutine print_stmt>)

=item * disconnecting from an Oracle DBMS instance (L<dbms_disconnect|Subroutine dbms_disconnect>)

=back

The following tasks are left to the user of ORADBB:

=over

=item * handling transactions through commit, rollback or savepoint. ORADBB disables automatic commit of SQL statements that start a transactions (e.g. INSERT, UPDATE, DELETE, MERGE), allowing the user to group multiple statements into a single transaction.

=item * output on bitmapped terminals through a graphical user interface

=back

While it is possible to use L<process_stmt|Subroutine process_stmt> to execute COMMIT and ROLLBACK, this may not be worth the effort of supplying all the parameters required. The recommended way to code COMMIT and ROLLBACK is to use the DBI subroutines C<commit> and C<rollback> directly, instead of through L<process_stmt|Subroutine process_stmt>. Thus COMMIT becomes:

 $dbh->commit;

and ROLLBACK becomes:

 $dbh->rollback;

Note that it is not necessary to load the DBI module through C<use DBI;> in order to call these subroutines.

=cut

package ORADBB;
use Exporter;
our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
# set the version for version checking
$VERSION     = 1.00;
@ISA = ('Exporter');
@EXPORT = qw(
build_connect_string
parse_connect_string
dbms_connect
dbms_disconnect
process_stmt
print_stmt
);

use warnings;
use strict;
use DBI;
# required for connect as sysdba
use DBD::Oracle qw(:ora_session_modes);
# not available in Perl distribution which ships with 10g
# use Term::ReadKey;

=head2 Subroutine parse_connect_string

Connect strings using remote operating system authentication such as 'C</@tns-service.world>' are not supported. These are a security risk and should not be used anyway.


=pod

 my ($connect_string, $ref_username, $ref_password, $ref_service_name, $ref_privilege, $ask_pwd)=@_;

=cut

# if $ask_pwd is true and $connect_string does not contain a password, then the password is asked for without
# echoing the input
sub parse_connect_string($$$$$$) {
	my ($connect_string, $ref_username, $ref_password, $ref_service_name, $ref_privilege, $ask_pwd)=@_;

	$connect_string=uc($connect_string);
	#print "connect_string passed: $connect_string\n";
	$$ref_username="";
	$$ref_password="";
	$$ref_service_name="";
	$$ref_privilege="NORMAL";
	
	my $idx;
	$idx=index($connect_string, " AS SYSDBA");
	if ( $idx >= 0 ) {
		$$ref_privilege="SYSDBA";
		$connect_string=substr($connect_string, $[, $idx);
		#print "connect_string contained AS SYSDBA; rest: $connect_string\n";
	} else {
		$idx=index($connect_string, " AS SYSOPER");
		if ( $idx >= 0 ) {
			$$ref_privilege="SYSOPER";
			$connect_string=substr($connect_string, $[, $idx);
			#print "connect_string contained AS SYSOPER; rest: $connect_string\n";
		}
	}
	my @split1=split(/\//, $connect_string);
	if ( $#split1 == 1 ) {
		$$ref_username=$split1[0];
		my @split2=split(/\@/, $split1[1]);
		$$ref_password=$split2[0];
		if ( $#split2 == 1 ) {
			$$ref_service_name=$split2[1];
		}
	} else {
		my @split2=split(/\@/, $connect_string);
		# change default only if split was successful
		#printf "\$#split2: %d\n", $#split2;
		if ( $#split2 >= 0 ) {
			$$ref_username=$split2[0];
		}
		# change default only if split was successful
		if ( $#split2 == 1 ) {
			$$ref_service_name=$split2[1];
		}
	}
	if ( $$ref_password eq "" && $ask_pwd ) {
		print "Password:";
		# Term::ReadKey not available in Perl distribution which ships with 10g
		#ReadMode('noecho');
		#$$ref_password=ReadLine(0);
		#ReadMode('normal');
		$$ref_password=<STDIN>;
		chomp $$ref_password;
	}
}

=head2 Subroutine dbms_connect

dbms_connect establishes a database session between a dababase client program and an Oracle database instance and returns a database handle (dbh) referencing the database session establised.

=pod

 $dbh=dbms_connect($username, $password, $service_name, $privilege);

Arguments:

=over 

=item $data_source

$data_sorce format is DBI:Oracle:<servicename> for
connecting locally or remotely through an Oracle TNS Listener.
servicename must be defined in tnsnames.ora or be resolved through some
other Oracle Naming Adapter.
$data_sorce format is DBI:Oracle: for
connecting to a local Oracle instance that is identified by environement
variable ORACLE_SID or windows registry key ORACLE_SID.

=item $username

$username is the database username

=item $password

$password is the password for the database user passed in $username

=back


=cut

# returns a database handle
sub dbms_connect ($$$$) {
	my ($username, $password, $service_name, $privilege)=@_;
	my $ora_session_mode;
	
	my $data_source="DBI:Oracle:" . $service_name;
	$privilege=uc($privilege);
	if ( $privilege eq "SYSDBA" ) {
		$ora_session_mode=ORA_SYSDBA;
	} elsif ( $privilege eq "SYSOPER" ) {
		$ora_session_mode=ORA_SYSOPER;
	} else {
		# DBD::Oracle does not define a constant for connecting "AS NORMAL"
		$ora_session_mode=0;
	}
	my $dbh = DBI->connect($data_source, $username, $password, 
			{ LongTruncOk => 1, 
			RaiseError => 1, 
			PrintError => 0, 
			AutoCommit => 0,
			ora_session_mode => $ora_session_mode} ) || 
	die "Error: dbms_connect failed to establish database session: $DBI::errstr";
	if ( defined $ENV{"ORADBB_TRACE_LEVEL"} ) {
		$dbh->do( qq(alter session set events '10046 trace name context forever, level $ENV{"ORADBB_TRACE_LEVEL"}') );
	}
	return $dbh;
}


=head2 Subroutine process_stmt

process_stmt executes arbitrary SQL statements against the DBMS instance referenced through the input argument $dbh.

=pod

 $dbh=($dbh, $ref_sth, $stmt_text, $ref_bind_vars, $ref_num_rows, $ref_error_msg, $ref_num_cols, $ref_col_heading, $ref_col_type, $ref_result_array, $ref_result_width);

=cut

sub process_stmt($$$$$$$$$$$) {
	my ($dbh, $ref_sth, $stmt_text, $ref_bind_vars, $ref_num_rows, $ref_error_msg, $ref_num_cols, $ref_col_heading, $ref_col_type, $ref_result_array, $ref_result_width)=@_;
	my ($error_code)=(0);
	eval {
		# to avoid unnecessary PARSE, prepare only if reference
		# to statement handle sth is undefined
		# if statement handle is already defined, reuse it and
		# do bind and execute right away without prepare
		if ( ! defined $$ref_sth ) {
			$$ref_sth = $dbh->prepare($stmt_text);
		}
		# bind variables if any
		foreach my $col_name (keys %$ref_bind_vars) {
			$$ref_sth->bind_param_inout(":$col_name", $ref_bind_vars->{$col_name}, 4000);
		}
		$$ref_sth->execute;
		$$ref_num_rows=$$ref_sth->rows;
	};
	if ($@) {
		# remove 'DBD ERROR: '
		$$ref_error_msg = $DBI::errstr;
		if ( defined $DBI::err ) {
			$$ref_error_msg =~ s/DBD ERROR: //;
			return $DBI::err;
		} else {
			$$ref_error_msg = $@;
			return -1;
		}
	} else {
		$$ref_error_msg="";
		if ( defined $$ref_sth->{NUM_OF_FIELDS} && $$ref_sth->{NUM_OF_FIELDS} > 0) {
			$$ref_num_cols=$$ref_sth->{NUM_OF_FIELDS};
			# this is a SELECT
			# printf "Fields %d\n", $$ref_sth->{NUM_OF_FIELDS};
		
			my $tmp_width=0;
			my $rownum_width=7;
			
				for (my $col_nr=0; $col_nr < $$ref_sth->{NUM_OF_FIELDS}; $col_nr++) {
					#printf "%dst column name: %s\n", $col_nr, $$ref_sth->{NAME}->[$col_nr];
					# initialize maximum widths as length of column headings
					$ref_result_width->[$col_nr]=length($$ref_sth->{NAME}->[$col_nr]);
					# set names of column headings
					$ref_col_heading->[$col_nr]=$$ref_sth->{NAME}->[$col_nr];
					#$ref_col_heading->[$col_nr]=$$ref_sth->{NAME}->[$col_nr] . " " . $$ref_sth->{TYPE}->[$col_nr];
					# set types of column headings
					$ref_col_type->[$col_nr]=$$ref_sth->{TYPE}->[$col_nr];
				}
				$$ref_num_rows=0;
				while ( my @row = $$ref_sth->fetchrow_array ) {
					for (my $j=0; $j < $$ref_sth->{NUM_OF_FIELDS}; $j++) {
						if ( defined $row[$j] ) {
							$tmp_width=length($row[$j]);
							$ref_result_array->[$$ref_num_rows][$j]= $row[$j];
						} else {
							$tmp_width=0;
							$ref_result_array->[$$ref_num_rows][$j]= "";
						}
						# print "length $tmp_width\n";
						if ($tmp_width > $ref_result_width->[$j]) {
							$ref_result_width->[$j]=$tmp_width;	
							# print "MaxW for col $j is $ref_result_width->[$j]\n";
						}
					}
					#printf("Row %d fetched. Hit return to continue fetching ...\n", $$ref_sth->rows);
					#my $answer=<STDIN>;
					$$ref_num_rows++;
				}
		} else {
				$$ref_num_cols=0;
		}
	}
	# finish does not DESTROY the handle nor close the cursor in Oracle.
	# It just changes the attribute Active, so doesn't appear to be necessary at all.
	# By default DBI destroys a handle, when it passes out of scope (see perldoc DBI),
	# info on handle attribute "InactiveDestroy"
	$$ref_sth->finish;
	return $error_code;
}

=head2 Subroutine print_stmt

Print_stmt outputs the result set of a SQL SELECT statement on an alphanumeric terminal. It prints column names as well as the rowcount. The widths of columns displayed is the maximum of the length of either the column name or the column data. Maximum column widths are computed 
by L<process_stmt|Subroutine process_stmt>. Print_stmt expects the column widths in the input parameter $ref_result_width.

 print_stmt($num_rows, $num_cols, $ref_col_heading, $ref_col_type, $ref_result_array, $ref_result_width);

=cut

sub print_stmt($$$$$$) {
	my ($num_rows, $num_cols, $ref_col_heading, $ref_col_type, $ref_result_array, $ref_result_width)=@_;
	if ($num_rows > 0 && $num_cols > 0) {
		my $alignment;
		# print column headings
		for (my $j=0; $j < $num_cols; $j++) {
			if ( $ref_col_type->[$j] == 8 || $ref_col_type->[$j] == 3 ) {
				# 8 float/number (no precision and scale specified with number)
				$alignment="";
			} else {
				$alignment="-";
			}
			printf "%${alignment}$ref_result_width->[$j]s ", $ref_col_heading->[$j];
		}
		print "\n";
		# print underline underneath column headings
		for (my $j=0; $j < $num_cols; $j++) {
			printf "%$ref_result_width->[$j]s ", "-" x $ref_result_width->[$j];
		}
		print "\n";
		# print column data
		for (my $i=0; $i < $num_rows; $i++) {
			for (my $j=0; $j < $num_cols; $j++) {
				if ( $ref_col_type->[$j] == 8 || $ref_col_type->[$j] == 3 ) {
					# 8 float/number (no precision and scale specified with number)
					$alignment="";
				} else {
					# type code as returned by DBD::Oracle
					# 110 interval day to second; causes warning:
					# Field 6 has an Oracle type (190) which is not explicitly supported at /usr/lib/perl5/site_perl/5.8/cygwin/DBD/Oracle.pm line 256, <STDIN> line 22.
					# 107 interval year to month; causes warning:
					# Field 5 has an Oracle type (189) which is not explicitly supported at /usr/lib/perl5/site_perl/5.8/cygwin/DBD/Oracle.pm line 256, <STDIN> line 22.
					# 95 timestamp with (local) timezone
					# 93 date/timestamp
					# 40 CLOB, NCLOB
					# 30 BLOB
					# 12 varchar
					# 3 integer/number(p,s)
					# 1 char/nchar
					# -1 long
					# -2 raw
					# -4 long raw
					# -9104 ROWID/UROWID
					# -9114 BFILE
					# binary_float (10g)
					# binary_double (10g)
					$alignment="-";
				}
				# NULL is a zero length string - do not attempt to print that
				printf "%${alignment}$ref_result_width->[$j]s ", $ref_result_array->[$i][$j];
			}
			print "\n";
		}
		printf "\n%d Row(s) processed.\n\n", $num_rows;
	}
}

=head2 Subroutine build_connect_string

Build_connect_string gleans the strings comprising an Oracle connect string from the command line arguments of a program.

 build_connect_string($ref_connect_string);

=cut

# supports '<username>/<password> as sysdba' (single quoted string) as well as <username>/<password> as sysdba (three separate arguments
sub build_connect_string($) {
	my ($ref_connect_string)=@_;
	$$ref_connect_string=$ARGV[0];
	if ( defined $ARGV[1] && uc($ARGV[1]) eq "AS" ) {
		$$ref_connect_string.=" " . $ARGV[1];
		if ( defined $ARGV[2] ) {
			$$ref_connect_string.=" " . $ARGV[2];
		}
	}
	#printf "connect_string: $$ref_connect_string\n";
}

=head2 Subroutine dbms_disconnect

Dbms_disconnect terminates a database session.

 dbms_disconnect($dbh);

=cut

sub dbms_disconnect($) {
	my ($dbh)=@_;
	$dbh->disconnect;
}	

# the following line is required to return a true value from this file
1;
