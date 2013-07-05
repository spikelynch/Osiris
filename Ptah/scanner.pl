#!/usr/bin/perl

use strict;
use Data::Dumper;
use FindBin;
use Cwd qw/realpath/;

use Dancer ":script";

use lib "$FindBin::Bin/../Osiris/lib";

use Osiris::App;
use Osiris::Job;
use Osiris::User;

my $appdir = realpath("$FindBin::Bin/..");


Dancer::Config::setting('appdir', $appdir);
Dancer::Config::load();

my $conf = config();

print Dumper({conf => $conf});
