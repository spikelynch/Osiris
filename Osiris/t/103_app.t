#!/usr/bin/perl

use Test::More;

use FindBin qw($Bin);


use strict;
use Data::Dumper;
use JSON;
use Text::CSV;
use Log::Log4perl;

use lib 'lib';

use Osiris::App;


my $LOG4J = "$Bin/log4perl.conf";
my $LOGGER = "Osiris.t.103_app";
Log::Log4perl->init($LOG4J);
my $log = Log::Log4perl->get_logger($LOGGER);


my $APPDIR = '/home/mike/Isis/isis/bin/xml/';
my $APPTOC = 'applicationTOC.xml';
my $APPCATS = 'applicationCategories.xml';
my $HTMLDIR = '/home/mike/workspace/DC18C Osiris/test/html/';

my $ONE_APP = undef; # 'cam2map';

my $CSV_DIAG = 'diag.csv';

opendir(my $dh, $APPDIR) || die("Couldn't open appdir");

my @appfiles = sort grep /^([a-zA-Z0-2]+)\.xml$/, readdir($dh);

my $napps = scalar(@appfiles) - 2;

plan tests => $napps * 5;

my $csv_data = [];

APP: for my $appfile ( @appfiles ) {

    next unless $appfile =~ /^([a-zA-Z0-2]+)\.xml$/;
	my $appname = $1;
	next if $appfile eq $APPTOC || $appfile eq $APPCATS;
	
    next if ( $ONE_APP && $appname ne $ONE_APP );

	my $app = Osiris::App->new(
		dir => $APPDIR,
		app => $appname
	);

    ok($app, "Created $appname Osiris::App") || die("Giving up");
	
	my $api = $app->read_form;
	
	ok($api, "Parsed app XML $appname");

	my $form = $app->form;
	
	ok($form, "Got app's form structure");

    my $guards = $app->guards;

    ok($guards, "Got app's guards");

    my $guards_json = encode_json($guards);

    ok($guards_json, "Encoded guards to JSON");


    for my $group ( @$form ) {
        for my $param ( @{$group->{parameters}} ) {
            if( $param->{filter} ) {
                push @$csv_data, [
                    $appname,
                    $group->{name},
                    $param->{name},
                    $param->{filter}
                ];
            }
        }
    }

}

my $csv = Text::CSV->new();

if( open(my $fh, ">:encoding(utf8)", $CSV_DIAG) ) {
    for my $row ( @$csv_data ) {
        $csv->print($fh, $row);
        print $fh "\n";
    }
    close $fh or diag("Error writing $CSV_DIAG: $!");
    diag("Wrote diagnostics file to $CSV_DIAG");
} else {
    diag("Error opening $CSV_DIAG: $!");
} 


diag("FIXME this isn't really much of a test script.");
