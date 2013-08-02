#!/usr/bin/perl

use Test::More tests => 17;

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

use_ok 'Osiris::User';

my $appdir = realpath("$FindBin::Bin/..");

my $TESTAPP = 'thm2isis';


Dancer::Config::setting('appdir', $appdir);
Dancer::Config::load();

my $conf = config();

ok(test_fixtures, "Build test fixtures");


my ( $apps, $browse ) = Osiris::load_toc(%$conf);

ok($apps, "Initialised list of Isis apps");

diag("isisdir: $conf->{isisdir}");

my $user = Osiris::User->new(
    id => $conf->{fakeuser},
    basedir => $conf->{workingdir},
    isisdir => $conf->{isisdir}
);

diag("user = $user");

ok($user, "Initialised user $conf->{fakeuser}");

my $job = $user->jobs->{1};

ok($job, "Got job from the joblist");

ok($job->{id}, "Job has an id");

cmp_ok($job->{status}, 'eq', 'new', "Job's status is 'new'");

ok($job->load_xml, "Loaded full job from XML");

ok($job->set_status(status => 'processing'), "Updated job status");

cmp_ok($job->{status}, 'eq', 'processing', "Job's status is 'processing'");

#### delete and start again

$user = undef;
$job = undef;

$user = Osiris::User->new(
    id => $conf->{fakeuser},
    basedir => $conf->{workingdir},
);

ok($user, "Initialised user");

$job = $user->jobs->{1};

ok($job, "Got job from the joblist");

ok($job->{id}, "Job has an id");


cmp_ok($job->{status}, 'eq', 'processing', "Job's status is 'processing'");

my $xmlfile = $job->xml_file;

ok($xmlfile, "Job has an xmlfile");

ok(-f $xmlfile, "xmlfile $xmlfile exists");

ok($job->load_xml, "Loaded job XML");
