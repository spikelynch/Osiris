#!/usr/bin/perl

use Test::More tests => 2;

use strict;
use Data::Dumper;

use lib 'lib';

use Osiris::App;

my $APPDIR = '/home/mike/Isis/isis/bin/xml/';
my $APPTOC = 'applicationTOC.xml';
my $APPCATS = 'applicationCategories.xml';
my $HTMLDIR = '/home/mike/workspace/DC18C Osiris/test/html/';

opendir(my $dh, $APPDIR) || die("Couldn't open appdir");
# sort readdir($dh)
for my $appfile ( 'cam2map.xml' ) {
	next unless $appfile =~ /^([a-zA-Z0-2]+)\.xml$/;
	my $appname = $1;
	next if $appfile eq $APPTOC || $appfile eq $APPCATS;
	
	my $app = Osiris::App->new(
		dir => $APPDIR,
		app => $appname
	);
	
	my $api = $app->parse_api;
	
	ok($api, "Parsed app XML $appname");


	my $form = $app->form;
	
	ok($form, "Got app's form structure");

	if( $appname eq 'cam2map' ) {
		for my $group ( @$form ) {
			print "Group $group->{name}\n";
			for my $param ( @{$group->{parameters}} ) {
				print "Param $param->{name}\n";
				print Dumper({param => $param});
				print "\n\n";
			}
		}
	}
}