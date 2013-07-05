#!/usr/bin/perl

use warnings;
use strict;

use POE;

use Data::Dumper;
use FindBin;

use Cwd qw/realpath/;
use Dancer ":script";

use lib "$FindBin::Bin/../lib";

use Osiris;
use Osiris::App;
use Osiris::Job;
use Osiris::User;



my $appdir = realpath("$FindBin::Bin/..");

Dancer::Config::setting('appdir', $appdir);
Dancer::Config::load();

my $conf = config();

my $POLLTIME = 5;

my $basedir = $conf->{workingdir};

POE::Session->create(
    inline_states => {
        _start => \&startup,
        scan_users => \&scan_users,
        scan_jobs => \&scan_jobs,
        fatal => \&fatal
    }
    );

POE::Kernel->run();
exit;

# Mandatory startup handler

sub startup {
    my ( $kernel, $heap ) = @_[KERNEL, HEAP];
    print "startup\n";

    $heap->{users} = {};
    $kernel->yield('scan_users');
}

# scan_users - get a list of users by scanning the
# working directory.

# this will add new users but not reap them if they go away,

sub scan_users {
    my ( $kernel, $heap ) = @_[KERNEL, HEAP];

    print "scan_users: $basedir\n";
    
    if( opendir(my $dh, $basedir) ) {
        ITEM: for my $item ( readdir($dh) ) {
            if( !$heap->{users}{$item} ) {
                next ITEM if $item =~ /^\./;
                print "DIR $basedir/$item\n";
                next ITEM unless -d "$basedir/$item";
                $heap->{users}{$item} = Osiris::User->new(
                    basedir => $basedir,
                    id => $item
                    );
            }
        }
        closedir($dh);
        $heap->{userids} = [ sort keys %{$heap->{users}} ];
        $kernel->yield('scan_jobs');
    } else {
        $heap->{error} = "Could not scan working dir $basedir $!";
        $kernel->yield('fatal');
    }
}

# scan_user - shift a user off the users array and scan it

sub scan_jobs {
    my ( $kernel, $heap ) = @_[KERNEL, HEAP];
    
    print "scan_jobs\n";
    print Dumper({heap => $heap});

    if( my $userid = shift @{$heap->{userids}} ) {
        print "user_id = $userid\n";
        my $user = $heap->{users}{$userid};
        my $jobs = $user->jobs;
        my @new = grep { $_->{status} eq 'new' } values %$jobs;
        for my $job ( @new ) {
            debug("new job", $job->{id});
        }
        $kernel->delay(scan_jobs => $POLLTIME);
    } else {
        $kernel->delay(scan_users => $POLLTIME);
    }
}


sub fatal {
    my ( $kernel, $heap ) = @_[KERNEL, HEAP];

    error("Fatal error: $heap->{error}");
    die(-1);
}


