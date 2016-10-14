#!/usr/bin/env perl
# $Id: args.pl,v 1.2 2007/08/07 13:27:11 ndebes Exp ndebes $
# $Log: args.pl,v $
# Revision 1.2  2007/08/07 13:27:11  ndebes
# new release
#
# Revision 1.1  2007/08/07 13:25:03  ndebes
# Initial revision
#
print "Script name: $0\n";
for ($i=0; $i < 10; $i++) {
	if (defined $ARGV[$i]) {
		printf "Argument %d: %s\n", $i, $ARGV[$i];
	}
}
