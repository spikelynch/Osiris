#!/usr/bin/perl

use strict;
use Data::Dumper;

use Dancer ':script';

use lib 'lib';

use Osiris::App;
use Osiris::Job;
use Osiris::User;

my $basedir = "$FindBin::Bin/../working";

opendir(my $dh, $basedir) || die ("Couldn't open $basedir: $!");

for my $item ( sort readdir($dh) ) {
    next if $item =~ /^\./;

    if( $item =~ /^[a-z]+$/ && -d "$basedir/$item" ) {

        my $user = Osiris::User->new(
            basedir => $basedir,
            id => $item
            );

        my $jobs = $user->jobs;

        my @new = grep { $_->{status} eq 'new' } values %$jobs;

        for my $job ( @new ) {
            $job->load;
            print "$user->{id}: ";
            print join(' ', $job->command) . "\n";
        }
    }
}
