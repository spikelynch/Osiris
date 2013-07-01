#!/usr/bin/perl

use strict;

use XML::Twig;
use Data::Dumper;

my $DIR = '/home/mike/Isis/isis/bin/xml/';

my %options = (
    ForceArray => 1
    );

my $count = 0;

my $dh;

opendir($dh, $DIR) || die("Couldn't open $DIR $!");

my $elts = {};

my $tw = XML::Twig->new(
    twig_handlers => {
        


);



for my $file ( sort readdir($dh) ) {
    next if $file =~ /^\./;
    next if $file =~ /^application/;
    

    
    $count++;
}

closedir($dh);


print "Apps: $count\n";
