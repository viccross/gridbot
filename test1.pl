#!/usr/bin/perl

use strict;
use warnings;

local $/ = ' ';
my @stuff = `vmcp q n`;

foreach (@stuff) { s/DSC\n//g; }
foreach (@stuff) { s/-L.{4}\n//g; }

@stuff = grep { $_ =~ /^GN2C/ } @stuff;

foreach my $name (@stuff) {
  print "$name\n"
}

