#!/usr/bin/perl

use Test::More;

use strict;
use Data::Dumper;
use JSON;

use lib 'lib';

use Osiris::App;

my $APPDIR = '/home/mike/Isis/isis/bin/xml/';
my $APPTOC = 'applicationTOC.xml';
my $APPCATS = 'applicationCategories.xml';
my $HTMLDIR = '/home/mike/workspace/DC18C Osiris/test/html/';

my $ONE_APP = 'isis2std'; # undef; # 'cam2map';

opendir(my $dh, $APPDIR) || die("Couldn't open appdir");

my @appfiles = sort grep /^([a-zA-Z0-2]+)\.xml$/, readdir($dh);

my $napps = scalar(@appfiles) - 2;

plan tests => $napps * 4;

open(my $fh, ">output.txt") || die;

for my $appfile ( @appfiles ) {

	diag("appfile = $appfile");
    next unless $appfile =~ /^([a-zA-Z0-2]+)\.xml$/;
	my $appname = $1;
	next if $appfile eq $APPTOC || $appfile eq $APPCATS;
	
    next if ( $ONE_APP && $appname ne $ONE_APP );

	my $app = Osiris::App->new(
		dir => $APPDIR,
		app => $appname
	);
	
	my $api = $app->read_form;
	
	ok($api, "Parsed app XML $appname");

	my $form = $app->form;
	
	ok($form, "Got app's form structure");

    my $guards = $app->guards;

    ok($guards, "Got app's guards");

    print $fh Dumper({ form => $form }) . "\n\n";


    print $fh Dumper({ guards => $guards }) . "\n\n";

    my $guards_json = encode_json($guards);

    ok($guards_json, "Encoded guards to JSON");

}

close $fh;

diag("FIXME this isn't really much of a test script.");
