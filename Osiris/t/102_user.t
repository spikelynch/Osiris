#!/usr/bin/perl

use Test::More tests => 12;

use strict;
use Data::Dumper;
use FindBin;
use Cwd qw/realpath/;
use Dancer ":script";
use Log::Log4perl;

use lib "$FindBin::Bin/../lib";

use Osiris;
use Osiris::App;
use Osiris::Job;
use Osiris::Test qw(test_fixtures);

my $appdir = realpath("$FindBin::Bin/..");


my $USER = 'michael';

my $TESTAPP = 'thm2isis';

my %TEST_PARAMETERS = (
    TO => 'output.cub',
    TIMEOFFSET => 0.0
);

my %TEST_FILES = (
    FROM => {
        file => "$appdir/../test/V03537002EDR.QUB",
        filename => "V03537002EDR.QUB"
    }
);


use_ok 'Osiris::User';

my $appdir = realpath("$FindBin::Bin/..");

Dancer::Config::setting('appdir', $appdir);
Dancer::Config::load();

my $conf = config();

ok(test_fixtures(), "Rebuilt test fixtures");

my $user = Osiris::User->new(
    id => $USER,
    basedir => $conf->{workingdir},
);

ok($user, "Initialised user");

my $jobs = $user->jobs;

ok(!scalar keys %$jobs, "Empty joblist");

my $app = Osiris::App->new(
    app => $TESTAPP,
    dir => $conf->{isisdir},
    brief => "Brief"
);

ok($app, "Initialised app");

my $job = $user->create_job(
     app => $app,
     parameters => \%TEST_PARAMETERS,
     uploads => \%TEST_FILES
    );

ok($job, "Created a new job");

 
