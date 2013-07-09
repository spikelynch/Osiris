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
use Osiris::Test;

use_ok 'Osiris::User';

my $appdir = realpath("$FindBin::Bin/..");

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


Dancer::Config::setting('appdir', $appdir);
Dancer::Config::load();

my $conf = config();

my ( $apps, $browse ) = Osiris::load_toc(%$conf);

ok($apps, "Initialised list of Isis apps");

my $user = Osiris::User->new(
    id => $conf->{fakeuser},
    basedir => $conf->{workingdir},
);

ok($user, "Initialised user");

my $app = Osiris::App->new(
    app => $TESTAPP,
    dir => $conf->{isisdir},
    brief => $apps->{$TESTAPP}
);

ok($app, "Initialised app");

my $job = $user->create_job(
     app => $app,
     parameters => \%TEST_PARAMETERS,
     uploads => \%TEST_FILES
    );

ok($job, "Created a new job");

ok($job->{id}, "Job has an id");

my $xmlfile = $job->xmlfile;

ok($xmlfile, "Job has an xml file");

ok(-f $xmlfile, "Xml file exists");

my $joblist = $user->_joblistfile;

ok(-f $joblist, "User's job list file exists");

my $jobsf = {};

# hack: the joblist is now XML

if ( open(JOBS, $joblist) ) {
    while( <JOBS> ) {
        chomp;
        if( /id="(\d+)".*status="([a-z]+)"/ ) {
            $jobsf->{$1} = $2;
        }
    }
    close(JOBS);
} else {
    die("Couldn't open job list");
}

ok(keys %$jobsf, "At least one job in job list");

ok(exists $jobsf->{$job->{id}}, "Found this job's id in job list");

cmp_ok($jobsf->{$job->{id}}, 'eq', 'new', "Job's status is 'new'");

my $id = $job->{id};

$job = undef;


$user = undef;

$user = Osiris::User->new(
    id => $conf->{fakeuser},
    basedir => $conf->{workingdir},
);

ok($user, "Initialised user (again)");

my $jobs = $user->jobs;

ok($jobs, "Got joblist from user") || die;

$job = $jobs->{$id};

ok($job, "Got job $id from job list");

$job->load_xml();

my $command = $job->command;

ok($command, "Got command arrayref");

diag(join(' ', @$command));

exec(@$command);
