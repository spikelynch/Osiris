#!/usr/bin/perl

use Test::More tests => 2;
use strict;
use warnings;

use strict;
use FindBin;
use Cwd qw/realpath/;
use Dancer ":script";
use Log::Log4perl;


use lib "$FindBin::Bin/../lib";


# the order is important
use Osiris;
use Dancer::Test;

route_exists [GET => '/'], 'a route handler is defined for /';
response_status_is ['GET' => '/'], 200, 'response status is 200 for /';
