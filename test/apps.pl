#!/usr/bin/perl

use strict;

use XML::Simple;
use Data::Dumper;

my $DIR = '/home/mike/Isis/isis/bin/xml/';


my $dh;

opendir($dh, $DIR) || die("Couldn't open $DIR $!");

for my $file ( readdir($dh) ) {
    next if $file =~ /^\./;
    next if $file =~ /^application/;

    my $xml = XMLin("$DIR$file") || die ("Parse error on $file");

    print Dumper({$file => $xml}) . "\n\n";

}

closedir($dh);
