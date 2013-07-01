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

for my $appfile ( sort readdir($dh) ) {
	next unless $appfile =~ /^([a-zA-Z0-2]+)\.xml$/;
	my $appname = $1;
	next if $appfile eq $APPTOC || $appfile eq $APPCATS;
	
	my $app = Osiris::App->new(
		dir => $APPDIR,
		app => $appname
	);
	
	my $api = $app->parse_api;
	
	ok($api, "Parsed app XML $appname");

	print Dumper({app => $app});

	my $html = $app->form;
	
	ok($html, "Got app's HTML form");
	
	my $htmlfile = $HTMLDIR . $appname . ".html";

	if( ok(open(HTML, ">$htmlfile"), "Writing to $htmlfile") ) {
		print HTML $html;
		close HTML;
	} else {
		diag("Couldn't open $htmlfile $!");
	}
	die;
}