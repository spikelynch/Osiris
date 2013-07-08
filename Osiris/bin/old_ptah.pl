#!/usr/bin/perl

use warnings;
use strict;

sub POE::Kernel::ASSERT_EVENTS() { 1 }
use POE qw(Wheel::Run);

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

my $POLLTIME = 3;

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
    $heap->{isis} = {};

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

    if( my $userid = shift @{$heap->{userids}} ) {
        print "user_id = $userid\n";
        my $user = $heap->{users}{$userid};
        print "heap user = $user\n";
        
        my $jobs = $user->jobs(reload => 1);
        my @new = values %$jobs;
        for my $job ( @new ) {
            $job->load_xml;
            print "New job: $job->{id}\n";
            my $jobid = join('.', $userid, $job->{id});
            my $command = $job->command;
            if( $command && @$command ) {
                $user->set_job_status(
                    jobid => $job->{id},
                    status => 'processing'
                );
                my $child = POE::Wheel::Run->new(
                    Program => sub {
                        print "Running subprocess...\n";
                        chdir $user->{dir} or die(
                            "Can't chdir to $user->{dir} $!"
                        );
                        exec @$command;
                        die("Exec failed: $!");
                    },
                    StdoutEvent  => "isis_stdout",
                    StderrEvent  => "isis_stderr",
                    # FIXME error event
                    );
                $heap->{isis}{$child->ID} = {
                    child => $child,
                    jobid => $jobid
                };
                debug("jobid = $jobid; wheelid = " . $child->ID . "; pid = " . $child->PID);
                # need this so that the process gets reaped
                $heap->{pid_to_wid}{$child->PID} = $child->ID;
                $kernel->sig_child($child->PID, "sig_child");
            } 
        }
        #$kernel->yield('scan_jobs');
        $kernel->delay(scan_jobs => $POLLTIME);
    } else {
        # no more users: go back up and rescan the directory
        #$kernel->yield('scan_users');
        $kernel->delay(scan_users => $POLLTIME);
    }
}

# handlers for child process events
# question: can they be related back to the ids?

sub isis_stdout {
    my ( $heap, $stdout, $wid ) = @_[HEAP, ARG0, ARG1];
    die;
    my $jobid = $heap->{isis}{$wid}{jobid};
    print "[$jobid]stdout> $stdout\n";
}


sub isis_stderr {
    my ( $heap, $stderr, $wid ) = @_[HEAP, ARG0];
    die;
    my $jobid = $heap->{isis}{$wid}{jobid};
    print "[$jobid]stderr> $stderr\n";
}

sub sig_child {
    my ($heap, $sig, $pid, $exit_val) = @_[HEAP, ARG0, ARG1, ARG2];
    die;
    print "sig_child: $pid\n";
    if( my $wid = $heap->{pid_to_wid}{$pid} ) {
        print "$$: Child $pid/$wid exited\n";
        my $isis = $heap->{isis}{$wid};
        my $jobid = $isis->{jobid};
    
        my ( $userid, $id ) = split('.', $jobid);
        if( my $user = $heap->{users}{$userid} ) {
            $user->set_job_status(jobid => $id, status => 'done');
        } else {
            error("User went missing while job was running!");
        }
        delete $heap->{isis}{$wid};
    }
}



sub fatal {
    my ( $kernel, $heap ) = @_[KERNEL, HEAP];

    error("Fatal error: $heap->{error}");
    die(-1);
}


