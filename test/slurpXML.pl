#!/usr/bin/perl

use strict;

use XML::Simple;
use Data::Dumper;

my $DIR = '/home/mike/Isis/isis/bin/xml/';
my $TOC = 'applicationTOC.xml';
my $CAT = 'applicationCategories.xml';

my $toc = XMLin("$DIR$TOC") || die;

my $apps = $toc->{application};
my $browse = {
	category => {},
	mission => {}
};

for my $app ( keys %$apps ) {
	my $cats = $apps->{$app}{category};
	my $desc = $apps->{$app}{brief};
	$desc =~ s/^\s+//g;
	$desc =~ s/\s+$//g;

	for my $what ( qw(category mission) ) {
		my $key = $what . 'Item';
		if ( my $items = $cats->{$key} ) {
			if( !ref($items) ) {
				$items = [ $items ];
			}
			for my $item ( @$items ) {
				$browse->{$what}{$item}{$app} = 1;
			}
		}
	}
	$apps->{$app} = $desc;
}

print Dumper({apps => $apps}) . "\n\n";

print Dumper({cats => $browse}) . "\n\n";



