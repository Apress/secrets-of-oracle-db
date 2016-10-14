#!/usr/bin/env perl

=for commentary

RCS Keys: $Header: /cygdrive/c/home/ndebes/it/perl/RCS/img_load_improved.pl,v 1.2 2007/11/08 17:15:42 ndebes Exp ndebes $

include the lib directorey from the ExifTool installation in PERL5LIB.
e.g. for Windows:
set PERL5LIB=C:\Programme\Oracle\product\db10.2\perl;C:\Programme\Oracle\product\db10.2\perl\site;C:\home\ndebes\it\perl\Image-ExifTool-7.00\lib

slow version:
parse repeatedly
select seq separately
select lob loc separately
seq nocache
lob nocache and no separate segment
default SDU, TDU
commit after each LOB

better version:
read 1 MB from image file at a time
parse once
use INSERT RETURNING
cached sequence
LOB cached and in separate segment witch larger chunk size
increased SDU and TDU
commit once at end

10.2.0.1.0 ships with DBI Version: 1.41 DBD::Oracle Version: 1.15

CREATE TABLE images(
	id number,
	date_loaded date,
	exif_make varchar2(30),
	exif_model varchar2(30),
	exif_create_date date,
	exif_iso varchar2(30),
	exif_f_number varchar2(30),
	exif_exposure_time varchar2(30),
	exif_35mm_focal_length varchar2(30),
	image_data BLOB,
	CONSTRAINT images_pk PRIMARY KEY(id)
)
-- default is NOCACHE
LOB (image_data) STORE AS images_image_data;

CREATE SEQUENCE image_id_seq NOCACHE;

SELECT id, date_loaded, exif_make, exif_model, exif_create_date, exif_iso, exif_f_number, exif_exposure_time, exif_35mm_focal_length
FROM images;

Improvements:
ALTER SYSTEM SET db_16k_cache_size=50m SCOPE=SPFILE;

CREATE TABLESPACE lob_ts DATAFILE 'C:\ORADATA\TEN\LOB_TS.DBF' SIZE 1g BLOCKSIZE 16384;

ALTER TABLE images MOVE LOB (image_data) STORE AS (TABLESPACE lob_ts DISABLE STORAGE IN ROW CACHE RETENTION CHUNK 32768);

ALTER SEQUENCE image_id_seq CACHE 1000;

=cut

use Image::ExifTool;
# crashes when use strict comes before use Image::ExifTool
use strict;
use DBD::Oracle qw(:ora_types);

sub print_usage() {
        print "Usage: $0 iterations jpeg-file\n";
}


sub ilo_mark_all_tasks_interesting($) {
	my ($dbh)=@_;
	our $ilo_config_sth;
	if (! defined $ilo_config_sth) {
		$ilo_config_sth=$dbh->prepare(q{
			begin
				hotsos_ilo_timer.set_mark_all_tasks_interesting(mark_all_tasks_interesting=>true,
				ignore_schedule=>true);
			end;
		});
	}
	$ilo_config_sth->execute;
}

sub ilo_begin_task($$$$$) {
	my ($dbh, $module, $action, $client_id, $comment)=@_;
	our $ilo_begin_task_sth;
	if (! defined $ilo_begin_task_sth) {
		$ilo_begin_task_sth=$dbh->prepare(q{
		CALL HOTSOS_ILO_TASK.BEGIN_TASK(:module, :action, :client_id, :a_comment)
		});
	}
	$ilo_begin_task_sth->bind_param(":module", $module);
	$ilo_begin_task_sth->bind_param(":action", $action);
	$ilo_begin_task_sth->bind_param(":client_id", $client_id);
	$ilo_begin_task_sth->bind_param(":a_comment", $comment);
	$ilo_begin_task_sth->execute;
}

sub ilo_end_task($) {
	my ($dbh)=@_;
	our $ilo_end_task_sth;
	if (! defined $ilo_end_task_sth) {
		$ilo_end_task_sth=$dbh->prepare(q{
		CALL HOTSOS_ILO_TASK.END_TASK()
		});
	}
	$ilo_end_task_sth->execute;
}

# check command line argument, $# is last index of array used, so 0 for 1 argument
# no arguments gives $# = -1
if ( $#ARGV < 0 ) {
        print_usage;
        exit 1;
}


print "DBI Version: $DBI::VERSION\n";
my ($module, $action, $client_id, $comment)=("img_load", undef, undef, undef);
my $dbh = DBI->connect(undef, undef, undef, { RaiseError => 1, AutoCommit => 0, PrintError => 0 , ora_module_name => $module} ) || die "Database connection not made: $DBI::errstr";
print "DBD::Oracle Version: $DBD::Oracle::VERSION\n";

# enable tracing with ILO if env. var. is set
if ( $ENV{SQL_TRACE_LEVEL} == 12 ) {
	$dbh->do("alter session set tracefile_identifier='img_load_imp'");
	ilo_mark_all_tasks_interesting($dbh);
}
# ILO adds overhead (e.g. additional exec calls, round-trips), this level enables level 8 SQL trace
if ( $ENV{SQL_TRACE_LEVEL} == -8 ) {
	$dbh->do("alter session set tracefile_identifier='img_load_improved'");
	$dbh->do("alter session set events '10046 trace name context forever, level 8'");
}
if ( $ENV{SQL_TRACE_LEVEL} > 0 ) {
	# begin task without any action, needed to enable SQL trace for the whole time
	ilo_begin_task($dbh, $module, $action, $client_id, $comment);
}

my $sth = $dbh->prepare(q{INSERT INTO images (id, date_loaded, exif_make, exif_model, exif_create_date, exif_iso, exif_f_number, exif_exposure_time, exif_35mm_focal_length, image_data) VALUES(image_id_seq.NEXTVAL, sysdate, :exif_make, :exif_model, to_date(:exif_create_date, 'yyyy:mm:dd hh24:mi:ss'), :exif_iso, :exif_f_number, :exif_exposure_time, :exif_35mm_focal_length, empty_blob()) RETURNING id, rowid INTO :id, :row_id
});
my $sel_sth = $dbh->prepare(q{SELECT image_data FROM images WHERE rowid=:row_id}, { ora_auto_lob => 0 });

# iterations passed with first parameter
for (my $i=0; $i < $ARGV[0]; $i++) {
	# SQL_TRACE_LEVEL=1 also instruments file operations
	if ( $ENV{SQL_TRACE_LEVEL} > 1 ) {
		$action="read_exif";
		ilo_begin_task($dbh, $module, $action, $client_id, $comment);
	}
	# LOB file name is second parameter
	open (LOBFILE, $ARGV[1]) or die "Could not open jpeg file\n";
	
	# get EXIF data from JPEF file
	my $exifTool = new Image::ExifTool;
	$exifTool->Options(Unknown => 1);
	my $info = $exifTool->ImageInfo(\*LOBFILE);
	if ( $ENV{SQL_TRACE_LEVEL} > 1 ) {
		ilo_end_task($dbh);
	}

	if ( $ENV{SQL_TRACE_LEVEL} > 0 ) {
		$action="exif_insert_imp";
		ilo_begin_task($dbh, $module, $action, $client_id, $comment);
	}
	my $image_id_seq_val;
	my ($lob_loc, $row_id, $data, $exif_make, $exif_model, $exif_create_date, $exif_iso, $exif_f_number, $exif_exposure_time, $exif_35mm_focal_length);
	my $total_bytes=0;
	
	$sth->bind_param(":exif_make", $info->{"Make"});
	$sth->bind_param(":exif_model", $info->{"Model"});
	$sth->bind_param(":exif_create_date", $info->{"CreateDate"});
	$sth->bind_param(":exif_iso", $info->{"ISO"});
	$sth->bind_param(":exif_f_number", $info->{"FNumber"});
	$sth->bind_param(":exif_exposure_time", $info->{"ExposureTime"});
	$sth->bind_param(":exif_35mm_focal_length", $info->{"FocalLengthIn35mmFormat"});
	$sth->bind_param_inout(":row_id", \$row_id, 18);
	$sth->bind_param_inout(":id", \$image_id_seq_val, 38);
	$sth->execute;
	#print $row_id, "\n";
	$sel_sth->bind_param(":row_id", $row_id);
	$sel_sth->execute;
	$sel_sth->bind_col(1, \$lob_loc);
	$sel_sth->fetchrow_array;
	#print $lob_loc, "\n";
	
	if ( $ENV{SQL_TRACE_LEVEL} > 0 ) {
		ilo_end_task($dbh);
		$action="lob_load_imp";
		ilo_begin_task($dbh, $module, $action, $client_id, $comment);
	}
	
	my $bytes_read;
	do {
		$bytes_read=sysread(LOBFILE, $data, 1048576);
		#print "bytes_read: $bytes_read\n";
	        $total_bytes+=$bytes_read;
		if ($bytes_read > 0) {
	        	my $rc = $dbh->ora_lob_append($lob_loc, $data);
			#print "rc: $rc\n";
		}
	} until $bytes_read <=0;

	if ( $ENV{SQL_TRACE_LEVEL} > 0 ) {
		ilo_end_task($dbh);
	}

}
# improved version commits once
$dbh->commit;
$sth->finish;
$sel_sth->finish;

#print "Hit return to quit program\n";
#my $answer=<STDIN>;
if ( $ENV{SQL_TRACE_LEVEL} > 0 ) {
	# end the task associated with the module and empty action
	ilo_end_task($dbh);
}
$dbh->disconnect;
