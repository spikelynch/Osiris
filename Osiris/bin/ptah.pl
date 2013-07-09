#!/usr/bin/perl

use warnings;
use strict;


sub POE::Kernel::ASSERT_DEFAULT () { 1 };
use POE qw(Wheel::Run);

use lib '/home/mike/workspace/DC18C Osiris/Osiris/lib';

use Data::Dumper;
use Log::Log4perl;

Log::Log4perl::init('/home/mike/workspace/DC18C Osiris/Osiris/environments/log4perl.conf');

use Osiris::Test qw(test_fixtures);
use Osiris::User;
use Osiris::Job;

sub MAX_CONCURRENT_TASKS () { 3 }

# Previous attempts to write ptah.pl keep getting a weird bug where
# child processes don't report back via either closeEvent or SIG_CHLD.

# This is an attempt to build ptah.pl from a working example 
# of a POE process controller step by step, so that I can identify
# where sig_childs stop working.

# Principle: make all the methods as short and simple as possible.
# Instead of loops, use heap variables as queues:

# $heap->{users}  - list of user IDs

# $heap->{jobs} - list of new jobs

# main loop pulls jobs off {jobs} until it's empty.

# then pull a {user} off and repopulate {jobs}

# if {user} is empty, rescan the working dir and start again.

my $WORKING_DIR = '/home/mike/workspace/DC18C Osiris/working/';


my $log = Log::Log4perl->get_logger('ptah');



$log->debug("Resetting fixtures...\n");

test_fixtures();


# Start the session that will manage all the children.  The _start and
# next_task events are handled by the same function.

POE::Session->create(
  inline_states => {
    _start      => \&initialise,
    scan_users  => \&scan_users,
    scan_jobs   => \&scan_jobs,
    run_jobs    => \&run_jobs,
    task_result => \&handle_task_result,
    task_done   => \&handle_task_done,
    task_debug  => \&handle_task_debug,
    sig_child   => \&sig_child,
    bail_out    => \&bail_out,
    _stop       => \&stop_ptah,
  }
);



sub initialise {
    my ( $kernel, $heap ) = @_[KERNEL, HEAP];

    $log->debug("[initialise]");

    $heap->{jobs} = [];
    $heap->{users} = [];
    $kernel->yield('scan_users');
}



# scan_users

# Event handler called when the job queue and user queues are both empty.
# Scans the working directory for user dirs and initialises Osiris::User
# objects for them.

# If it finds nothing, it calls itself on a delay.


sub scan_users {
    my ( $kernel, $heap, $state, $sender, @caller ) = 
        @_[KERNEL, HEAP, STATE, SENDER, CALLER_FILE, CALLER_LINE, CALLER_STATE];
    $log->debug("___[scan_users]");
    $log->debug("    state = $state");
    $log->debug("    sender = $sender");
    $log->debug("    caller = " . join(', ', @caller));

    $log->debug("Scanning dir $WORKING_DIR");
    opendir(my $dh, $WORKING_DIR) || do {
        $log->fatal("Couldn't opendir $WORKING_DIR");
        die;
    };

    $heap->{users} = [];
    ITEM: for my $id ( readdir($dh ) ) {
        $log->debug("Item $id");
        next ITEM if $id =~ /^\./;
        next ITEM if ! -d "$WORKING_DIR/$id";
        my $user = Osiris::User->new(
            id => $id,
            basedir => $WORKING_DIR
            );
        $log->debug("Got user $id");
        push @{$heap->{users}}, $user;
    }
    closedir($dh);

    if( !@{$heap->{users}} ) {
        $log->warn("No users found.");
        $kernel->delay(scan_users => 10);
    } else {
        $kernel->yield('scan_jobs');
    }
}
    

# Event handler called when the job queue is empty.  It shifts the next
# user off the user queue and scans their job list for new jobs.

# If there is no next user, it calls scan_users.


sub scan_jobs {
    my ( $kernel, $heap, $state, $sender, @caller ) = 
        @_[KERNEL, HEAP, STATE, SENDER, CALLER_FILE, CALLER_LINE, CALLER_STATE];

    $log->debug("___[scan_jobs]");
    $log->debug("    state = $state");
    $log->debug("    sender = $sender");
    $log->debug("    caller = " . join(', ', @caller));

    my $user = shift @{$heap->{users}};
    if( $user ) {

        my $all_jobs = $user->jobs(reload => 1);
        
        my @new = grep { $_->{status} eq 'new' } values %$all_jobs;

        $log->debug("New jobs = " . join(' ', map { $_->{id} } @new));

        for my $newjob ( @new ) {
            $log->debug("New job $newjob $newjob->{id} $newjob->{status}");
        }

        push @{$heap->{jobs}}, @new;

        $kernel->yield('run_jobs');
    } else {
        $kernel->delay('scan_users' => 5);
    }
}


# run_jobs

# Pulls items off the job queue until either
#
# (a) MAX_CONCURRENT TASKS is reached, in which case it does nothing
#    (when a running job is finished it will call run_jobs again)
# (b) there are no more jobs, in which case it calls scan_jobs to get more
#    jobs from the next user.

sub run_jobs {
    my ( $kernel, $heap, $state, $sender, @caller ) = 
        @_[KERNEL, HEAP, STATE, SENDER, CALLER_FILE, CALLER_LINE, CALLER_STATE];

    $log->debug("___[run_jobs]");
    $log->debug("    state = $state");
    $log->debug("    sender = $sender");
    $log->debug("    caller = " . join(', ', @caller));
    
    $log->debug("heap jobs = " . join(', ', $heap->{jobs}));
    $log->debug("running jobs " . scalar(keys %{$heap->{running}}));
    CAPACITY: while ( keys(%{$heap->{running}}) < MAX_CONCURRENT_TASKS ) {
       
        my $job = shift @{$heap->{jobs}};
        last CAPACITY unless defined $job;

        $log->debug("Running job $job->{id}");
        
        $job->load_xml;
        my $command = $job->command;
        $log->debug("Marking job status 'processing'");
        $job->set_status(status => 'processing') || die("Couldn't set status");
        $log->debug("Starting job for user $job->{user}{id}");
        my $task = POE::Wheel::Run->new(
            Program => sub {
                $log->debug(">In subprocess");
                my $dir = $job->working_dir;
                chdir $dir || die("Couldn't chdir to $dir");
                $log->debug(">" . join(' ', @$command));
                exec(@$command);
            },
            StdoutEvent  => "task_result",
            StderrEvent  => "task_debug",
            CloseEvent   => "task_done",
            );
        $log->debug("Launched task " . $task->ID . " with pid " . $task->PID);
        $heap->{running}{$task->ID} = {
            task => $task,
            job => $job
        };
        $heap->{pid_to_wid}{$task->PID} = $task->ID;
        $kernel->sig_child($task->PID, "sig_child");
    }
    $log->debug("end of run_jobs");
    if( !@{$heap->{jobs}} ) {
        $kernel->delay('scan_jobs' => 5);
    }
}


sub stop_ptah {
    my ( $kernel, $heap, $state, $sender ) = 
        @_[KERNEL, HEAP, STATE, SENDER];

    $log->debug("___[_stop_ptah]");
    $log->debug("    state = $state");
    $log->debug("    sender = $sender");
    print "End.\n";
}







# Handle information returned from the task.  Since we're using
# POE::Filter::Reference, the $result is however it was created in the
# child process.  In this sample, it's a hash reference.

sub handle_task_result {
    my ( $output, $wid ) = @_[ARG0, ARG1];
    print ">>>stdout $wid>>> $output\n";
}

# Catch and display information from the child's STDERR.  This was
# useful for debugging since the child's warnings and errors were not
# being displayed otherwise.

sub handle_task_debug {
    my ( $output, $wid ) = @_[ARG0, ARG1];
    print "stdout $wid $output\n";
}

# Mark the job 

sub handle_task_done {
  my ($kernel, $heap, $task_id) = @_[KERNEL, HEAP, ARG0];


  $kernel->yield("scan_jobs");
}

# Detect the CHLD signal as each of our children exits.
sub sig_child {
    my ($heap, $sig, $pid, $exit_val) = @_[HEAP, ARG0, ARG1, ARG2];

    $log->debug("sig_child caught for PID $pid");

    my $wid = $heap->{pid_to_wid}{$pid};


    if( !$wid ) {
        $log->error("Child $pid has no corresponding wheel ID");
    } else {
        $log->debug("Wheel id =  $wid");
        my $job = $heap->{running}{$wid}{job};
        $log->debug("Job from POE heap = $job $job->{id}");
        delete $heap->{running}{$wid};
        $log->debug("Setting job $job->{id} status to 'done'");
        $job->set_status(status => "done"); 
    }
}




$poe_kernel->run();
exit 0;

