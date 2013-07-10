#!/usr/bin/perl

use strict;

use Data::Dumper;
use FindBin;
use Cwd qw/realpath/;
use Dancer ":script";
use Log::Log4perl;

use lib "$FindBin::Bin/../lib";

use Osiris::Test qw(test_fixtures);

test_fixtures();

my $bin = "$FindBin::Bin/../bin";

my $cmd = "$bin/ptah.pl";

$cmd =~ s/\s/\\ /g;

print "Running $cmd\n";

exec($cmd);
