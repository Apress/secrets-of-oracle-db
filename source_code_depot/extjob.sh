# $Header: /cygdrive/c/home/ndebes/bin/RCS/extjob.sh,v 1.2 2007/12/21 21:08:18 ndebes Exp ndebes $
# run for example like this from Windows cmd.exe using Cygwin: 
# c:\programs\cygwin\bin\bash.exe -c "/cygdrive/c/home/ndebes/bin/extjob.sh  -d /tmp -s /tmp/env.sh env"
DEBUG=1 # set DEBUG=1 to enable debugging output
LOGDIR=/var/tmp # default directory for log files
PID=$$ # get process id
if [ $DEBUG -gt 0 ]; then
	echo "\$#=$#"
fi
if [ $# -lt 1 ]; then
	echo "Usage: $0 [-s envfile] [-d log_directory] command [arguments]" 1>&2
	RC=255
else
	RC=0
	while [ $RC = 0 ]; do
		getopts ":s:d:" OPTCHAR
		RC=$? # getopts returns 1, when all options have been processed
		if [ $DEBUG -gt 0 ]; then
			echo "RC=$RC OPTCHAR=$OPTCHAR OPTARG=$OPTARG OPTIND=$OPTIND"
		fi
		if [ $RC = 0 ]; then
			# an option, invalid or not, was found
			case $OPTCHAR in
				's')
					ENVFILE=$OPTARG
					;;
				'd')
					LOGDIR=$OPTARG
					;;
				'?')
					echo "$0: unknown option '$OPTARG'" 1>&2
					RC=255
					;;
			esac
		fi
	done
	if [ $DEBUG -gt 0 ]; then
		echo "ENVFILE=$ENVFILE"
		echo "LOGDIR=$LOGDIR"
	fi
	if [ $RC = 1 ]; then
		# source ENVFILE if option -s was passed, unless an invalid 
		# option was found (RC=255)
		if [ "$ENVFILE" != "" ]; then
			. $ENVFILE # todo: redirect stderr
		fi
		RC=$?
		if [ $RC = 0 ]; then
			# run the program
			# get arguments from shell variables $n
			ARGLIST=""
			for (( i=$OPTIND ; $i <= $#  ; i++)); do
				EXPR="echo \$$i"
				ARG=`eval $EXPR`
				if [ $DEBUG -gt 0 ]; then
					echo "EXPR=$EXPR"
					echo "ARG=$ARG"
				fi
				if [ "$ARG" = "" ]; then
					break;
				else
					ARGLIST="$ARGLIST $ARG"
					if [ $DEBUG -gt 0 ]; then
						echo "ARGLIST=$ARGLIST"
					fi
				fi
			done
			eval "$ARGLIST" 1>$LOGDIR/$PID.stdout.log 2>$LOGDIR/$PID.stderr.log
			RC=$?
		fi
	fi
	/usr/bin/head -c 180 $LOGDIR/$PID.stderr.log 1>&2 # get first 180 bytes of standard error output
	echo "" # append newline
	echo "PID=$PID" 1>&2 # write process id to standard error
	echo "RC=$RC" 1>&2 # write return code to standard error
	exit $RC
fi
