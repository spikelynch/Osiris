#!/usr/bin/perl

use strict;

use XML::Simple;
use Data::Dumper;

my $DIR = '/home/mike/Isis/isis/bin/xml/';

my %options = (
    ForceArray => 1
    );

my $count = 0;

my $dh;

opendir($dh, $DIR) || die("Couldn't open $DIR $!");

for my $file ( sort readdir($dh) ) {
 #   next unless $file =~ /hicrop/;
    next if $file =~ /^\./;
    next if $file =~ /^application/;
    
    my $xml = XMLin("$DIR$file", %options) || die ("Parse error on $file");

#    print Dumper({$file => $xml}) . "\n\n";
    $count++;
}

closedir($dh);


print "Apps: $count\n";
