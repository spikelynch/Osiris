#!/usr/bin/perl

use warnings;
use strict;




sub POE::Kernel::ASSERT_DEFAULT () { 1 };
use POE qw(Wheel::Run Filter::Reference);

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

my $isiscmd = {
    FROM => "$WORKING_DIR/V03537002EDR.QUB",
    TO => "$WORKING_DIR/V03537002.cub",
    TIMEOFFSET => '0.0'
};

my $log = Log::Log4perl->get_logger('ptah');


my @command = ( '/home/mike/Isis/isis/bin/thm2isis' );

for my $option ( keys %$isiscmd ) {
    push @command, "$option=$isiscmd->{$option}";
}

$log->debug("Resetting fixtures...\n");

test_fixtures();


# Start the session that will manage all the children.  The _start and
# next_task events are handled by the same function.

POE::Session->create(
  inline_states => {
    _start      => \&initialise,
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

    $heap->{user} = Osiris::User->new(
        id => 'michael',
        basedir => $WORKING_DIR
        );
    $heap->{jobs} = [];
    $kernel->yield('scan_jobs');
}



sub scan_jobs {
    my ( $kernel, $heap, $state, $sender, @caller ) = 
        @_[KERNEL, HEAP, STATE, SENDER, CALLER_FILE, CALLER_LINE, CALLER_STATE];


    
    $log->debug("[scan_jobs]");
    $log->debug("state = $state");
    $log->debug("sender = $sender");
    $log->debug("caller = " . join(', ', @caller));
    my $user = $heap->{user};  # scan_users

    my $all_jobs = $user->jobs(reload => 1);

    my @new = grep { $_->{status} eq 'new' } values %$all_jobs;

    $log->debug("New jobs = " . join(' ', map { $_->{id} } @new));

    for my $newjob ( @new ) {
        $log->debug("New job $newjob $newjob->{id} $newjob->{status}");
    }

    push @{$heap->{jobs}}, @new;

    if( @{$heap->{jobs}} ) {
        $kernel->delay('run_jobs' => 5);
    }# else {
     # $kernel->delay('scan_user' => 5);
    #}
}




sub run_jobs {
    my ( $kernel, $heap ) = @_[KERNEL, HEAP];
    
    $log->debug("[run_jobs]");

    $log->debug("heap jobs = " . join(', ', $heap->{jobs}));
    
    $log->debug("running jobs " . scalar(keys %{$heap->{running}}));
    while ( keys(%{$heap->{running}}) < MAX_CONCURRENT_TASKS ) {
        
        
        
        my $job = shift @{$heap->{jobs}};
        last unless defined $job;
        $log->debug("heap jobs 2 = " . join(', ', $heap->{jobs}));
        
        $log->debug("Running job $job->{id}");
        
        $job->load_xml;
        my $command = $job->command;
        $log->debug("Marking job status 'processing'");
        $job->set_status(status => 'processing') || die("Couldn't set status");
        $log->debug("Starting job: $command->[0]");
        my $task = POE::Wheel::Run->new(
            Program => sub {
                print "In the subprocess: chdir...\n";
                chdir $WORKING_DIR || die("Couldn't chdir to $WORKING_DIR");
                print "exec\n";
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
}


sub stop_ptah {
    my ( $kernel, $heap, $state, $sender ) = 
        @_[KERNEL, HEAP, STATE, SENDER];

    $log->debug("_stop_ptah");
    
    $log->debug("[scan_jobs]");
    $log->debug("state = $state");
    $log->debug("sender = $sender");
#    $log->debug("caller = " . join(', ', @caller));
    
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
