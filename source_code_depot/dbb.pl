#!/usr/bin/env perl
# $Header: /cygdrive/c/home/ndebes/it/perl/RCS/dbb.pl,v 1.11 2007/08/08 08:35:44 ndebes Exp ndebes $
# DBB - a database brower.
# Executes arbitrary statements through Perl DBI

use warnings;
use strict;
# use local Modules during development
# use lib sets path below at beginning of @INC
#use lib "/cygdrive/c/home/ndebes/it/perl";
#print join("\n", @INC) . "\n";
use ORADBB;

if ( $#ARGV < 0 ) {
	print "Usage: dbb.pl username[/password][\@tns_service_name] [AS {NORMAL | SYSDBA | SYSOPER} ]\n";
	print "Example: dbb.pl system/manager\@orcl.world\n";
	exit 1;
}


# read from STDIN until a / that is the first and only character on a line is found
# returns the length of the statement
sub read_stmt ($) {
	my ($ref_stmt_text)=@_;
	$$ref_stmt_text="";
	my $stmt_length=0;
	my $stmt_line="";
	my $line_length;
	printf "DBB> ";
	while(1) {
		$stmt_line=<STDIN>;
		if ( ! defined $stmt_line) {
			$$ref_stmt_text="";
			return 0;
		} elsif ($stmt_line eq "/\n") {
			return $stmt_length;
		} else {
			$$ref_stmt_text .= $stmt_line;
			$line_length=length($stmt_line);
			$stmt_length += $line_length;
		}
	}
	return $stmt_length;
}

my ($connect_string, $username, $password, $service_name, $privilege);
build_connect_string(\$connect_string);
#printf "connect_string: $connect_string\n";

parse_connect_string($connect_string, \$username, \$password, \$service_name, \$privilege, 1);

my $dbh = dbms_connect($username, $password, $service_name, $privilege);

my ($stmt_length, $stmt_text, $num_rows, $error_msg, $error_code)=(1, "", 0, "", 0);
my ($num_cols, @col_heading, @col_type, @result_array, @result_width, %bind_vars);

# main loop of the program
while ( $stmt_length > 0) {
	$stmt_length=read_stmt(\$stmt_text);
	if ( $stmt_length > 0 ) {
		# my ($dbh, $stmt_text, $ref_num_rows, $ref_error_msg, $ref_num_cols, $ref_col_heading, $ref_col_type, $ref_result_array, $ref_result_width)=@_;
		$error_code=process_stmt($dbh, undef, $stmt_text, \%bind_vars, \$num_rows, \$error_msg, \$num_cols, \@col_heading, \@col_type, \@result_array, \@result_width);
		if ( $error_code != 0 ) {
			printf "error code: %d, error message: %s\n\n", $error_code, $error_msg;
		} elsif ($num_cols > 0) {
			# my ($num_rows, $num_cols, $ref_col_heading, $ref_result_array, $ref_result_width)=@_;
			if ( $num_rows > 0) {
				print_stmt($num_rows, $num_cols, \@col_heading, \@col_type, \@result_array, \@result_width);
			} else {
				print "\nNo rows selected.\n\n"
			}
		} else {
			printf "\n%d Row(s) Processed.\n\n", $num_rows;
		}
	}
}
$dbh->disconnect;
exit;
