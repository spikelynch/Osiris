#!/usr/bin/perl

use Test::More tests => 1;
use strict;
use warnings;

use strict;
use FindBin;
use Cwd qw/realpath/;
use Dancer ":script";
use Log::Log4perl;

use lib "$FindBin::Bin/../lib";

use_ok 'Osiris';
