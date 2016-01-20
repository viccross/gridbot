#!/usr/bin/perl

use strict;
use warnings;

my @cpresult = `vmcp ind`;

my ($avgproc) = $cpresult[0] =~ /^AVGPROC-0*(.+)%/;
my ($paging) = $cpresult[2] =~ /^PAGING-(.+)\/SEC/;

foreach my $name (@cpresult) {
  print "$name";
#  if ( $avgproc = $name =~ /^AVGPROC-(.+)%/ ) {} ;
#  if ( $paging = $name =~ /^PAGING-(.+)\/SEC/ ) {} ;
}

print $avgproc;
print $paging;
