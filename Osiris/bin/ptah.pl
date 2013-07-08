#!/usr/bin/perl

use warnings;
use strict;

sub POE::Kernel::ASSERT_DEFAULT () { 1 };
#sub POE::Kernel::TRACE_DEFAULT  () { 1 };


use POE qw(Wheel::Run Filter::Reference);

use lib '/home/mike/workspace/DC18C Osiris/Osiris/lib';

use Osiris::Test qw(test_fixtures);


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

my $WORKING_DIR = '/home/mike/workspace/DC18C Osiris/working/michael/';

my $isiscmd = {
    FROM => '/home/mike/workspace/DC18C Osiris/working/michael/V03537002EDR.QUB',
    TO => '/home/mike/workspace/DC18C Osiris/working/michael/V03537002.cub',
    TIMEOFFSET => '0.0'
};


my @command = ( '/home/mike/Isis/isis/bin/thm2isis' );

for my $option ( keys %$isiscmd ) {
    push @command, "$option=$isiscmd->{$option}";
}

print "Resetting fixtures...\n";

test_fixtures();

print "Isis command: \n" . join(' ', @command) . "\n";

my $JOBS = [ \@command, \@command, \@command ];

my @tasks = qw(one two three four five six seven eight nine ten);

# Start the session that will manage all the children.  The _start and
# next_task events are handled by the same function.

POE::Session->create(
  inline_states => {
    _start      => \&initialise,
    next_task   => \&start_tasks,
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

    print "Initialise... \n";
    $heap->{jobs} = $JOBS;

    $kernel->yield('next_task');
}





sub start_tasks {
  my ( $kernel, $heap ) = @_[KERNEL, HEAP];

  print "start_tasks\n";
  while ( keys(%{$heap->{running}}) < MAX_CONCURRENT_TASKS ) {

    my $next_task = shift @{$heap->{jobs}};
    last unless defined $next_task;
    print "Starting task " . join(' ', @$next_task) . "\n";
    my $task = POE::Wheel::Run->new(
        Program => sub {
            print "In the subprocess\n";
            print "exec\n";
            exec(@$next_task);
        },
        StdoutEvent  => "task_result",
        StderrEvent  => "task_debug",
        CloseEvent   => "task_done",
    );
    print "Launched task " . $task->ID . "\n";
    $heap->{running}{$task->ID} = $task;
    $kernel->sig_child($task->PID, "sig_child");
  }
  print "end of start_tasks\n";
}


sub stop_ptah {
    print "End.\n";
}







sub infinite_tasks {
    return rand(10);
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

# The task is done.  Delete the child wheel, and try to start a new
# task to take its place.

sub handle_task_done {
  my ($kernel, $heap, $task_id) = @_[KERNEL, HEAP, ARG0];
  delete $heap->{task}->{$task_id};
  $kernel->yield("next_task");
}

# Detect the CHLD signal as each of our children exits.
sub sig_child {
  my ($heap, $sig, $pid, $exit_val) = @_[HEAP, ARG0, ARG1, ARG2];
  my $details = delete $heap->{$pid};

  print "$$: Child $pid exited\n";
}





$poe_kernel->run();
exit 0;

