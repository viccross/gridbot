#!/usr/bin/perl

use XML::Simple;
use Data::Dumper;

my $clusterxml  = `nc 172.31.3.101 8651`;
my $clusterdump = XMLin( $clusterxml );

print Dumper($clusterdump);

1;

