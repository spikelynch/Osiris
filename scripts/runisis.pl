#!/usr/bin/perl

use strict;

use lib 'lib';

use Osiris::Job;
use Osiris::User;

my $id = 'test';


my $user = Osiris::User->new(id => $id);

for my $job ( $user->jobs ) {
    $job->
