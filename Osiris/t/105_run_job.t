#!/usr/bin/perl

# Test script which creates a new job, runs the command (directly, not
# via ptah) and then checks to see that the job can associate all the
# output files. (Capturing stdout and stderr is left to the ptah tests).

use Test::More tests => 26;

use strict;
use Data::Dumper;
use FindBin;
use Cwd qw/realpath/;
use Dancer ":script";
use File::Copy;
use Log::Log4perl;

use lib "$FindBin::Bin/../lib";

use Osiris;
use Osiris::App;
use Osiris::Job;
use Osiris::Test qw(test_fixtures);

use_ok 'Osiris::User';

my $appdir = realpath("$FindBin::Bin/..");

my $INPUT_FILENAME = 'V03537002EDR.QUB';
my $OUTPUT_FILENAME = 'MYOUTPUT';
my $INPUT_FILE = '/home/mike/workspace/DC18C Osiris/test/' . $INPUT_FILENAME;

my $JOB_PARAMS = {
    TO => $OUTPUT_FILENAME,    # note '.cub' will be appended
    TIMEOFFSET => '0.0',
};



# This app happens to have a complicated output file case.

my $TESTAPP = 'thm2isis';

Dancer::Config::setting('appdir', $appdir);
Dancer::Config::load();

my $conf = config();


ok(test_fixtures, "Build test fixtures");


my ( $apps, $browse ) = Osiris::load_toc(%$conf);

ok($apps, "Initialised list of Isis apps");

my $app = Osiris::App->new(
    dir => $conf->{isisdir},
    app => $TESTAPP
);

ok($app, "Initialised app");


my $user = Osiris::User->new(
    id => $conf->{fakeuser},
    basedir => $conf->{workingdir},
);

ok($user, "Initialised user");

my $job = $user->create_job(app => $app);

ok($job, "Created job $job->{id}") || die("Bailing out");

ok(-d $job->working_dir, "Job's working dir exists");

my %params = %$JOB_PARAMS;

my $to_file = $job->working_dir(file => $INPUT_FILENAME);

ok(copy($INPUT_FILE, $to_file), "Copied $INPUT_FILE to $to_file") || do {
    diag("Copy failed: $!");
    die("Bailing out");
};

$params{FROM} = $to_file;

ok($job->add_parameters(parameters => \%params), "Added parameters");

ok($user->write_job(job => $job), "Wrote job");

cmp_ok($job->{status}, 'eq', 'new', "Job's status is 'new'");

my $command = $job->command;

ok($command, "Got command-line for job: " . join(' ', @$command)) || die(
    "Bailing out"
);

ok($job->set_status(status => 'processing'), "Updated job status");

cmp_ok($job->{status}, 'eq', 'processing', "Job's status is 'processing'");

my $dir = $job->working_dir;

ok($dir, "Got working directory");

ok(chdir $dir, "Moved to working directory") || die("Bailing out");

system(@$command);

my $files = $job->files;

ok($files->{print}, "Got print.prt");

cmp_ok($files->{inputs}{FROM}[0], 'eq', $INPUT_FILENAME, "Job files input = $INPUT_FILENAME");

ok(-f $job->working_dir(file => $INPUT_FILENAME), "File $INPUT_FILENAME exists");

my %OUTPUTS = (
    join('.', $OUTPUT_FILENAME, 'even', 'cub') => 1,
    join('.', $OUTPUT_FILENAME, 'odd', 'cub') => 1,
);


for my $ofile ( @{$files->{outputs}{TO}} ) {
    diag("Output file $ofile");
    ok($OUTPUTS{$ofile}, "Expected output file $ofile");
    delete $OUTPUTS{$ofile};
    ok(-f $job->working_dir(file => $ofile), "Output file $ofile exists");
}

ok(! keys %OUTPUTS, "Got all expected output files") || do {
    diag(Dumper({leftovers => \%OUTPUTS}));
};
    
   


ok($job->set_status(status => 'done'), "Updated job status to 'done'");



cmp_ok($job->{status}, 'eq', 'done', "Job's status is 'done'");
