#!/usr/bin/perl

use strict;
use Data::Dumper;
use FindBin;

use Cwd qw/realpath/;
use Dancer ":script";

use lib "$FindBin::Bin/../lib";

use Osiris;
#use Osiris::App;
#use Osiris::Job;
#use Osiris::User;

my $appdir = realpath("$FindBin::Bin/..");

Dancer::Config::setting('appdir', $appdir);
Dancer::Config::load();

my $conf = config();

my $basedir = $conf->{workingdir};


opendir(my $dh, $basedir) || die ("Couldn't open $basedir: $!");

for my $item ( sort readdir($dh) ) {
    next if $item =~ /^\./;

    if( $item =~ /^[a-z]+$/ && -d "$basedir/$item" ) {

        my $user = Osiris::User->new(
            basedir => $basedir,
            id => $item
            );

        my $jobs = $user->jobs;

        print Dumper({jobs => $jobs}) . "\n";

        my @new = grep { $_->{status} eq 'new' } values %$jobs;

        for my $job ( @new ) {
            $job->load_xml;
            print "$user->{id}: job $job->{id} ";
            print join(' ', @{ $job->command }) . "\n";
        }
    }
}
