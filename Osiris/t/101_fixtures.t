#!/usr/bin/perl

use Test::More tests => 1;

use strict;
use Data::Dumper;

use lib 'lib';

use Osiris::Test qw(test_fixtures);



ok( test_fixtures(), "Copied fixtures");

l
