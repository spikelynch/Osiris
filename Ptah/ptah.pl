#!/usr/bin/perl
# This program forks children to handle a number of slow tasks.  It
# uses POE::Filter::Reference so the child tasks can send back
# arbitrary Perl data.  The constant MAX_CONCURRENT_TASKS limits the
# number of forked processes that can run at any given time.

use warnings;
use strict;
use POE qw(Wheel::Run Filter::Reference);
sub MAX_CONCURRENT_TASKS () { 3 }

my @tasks = qw(one two three four five six seven eight nine ten);

# Start the session that will manage all the children.  The _start and
# next_task events are handled by the same function.

POE::Session->create(
    inline_states => {
        _start      => \&start_tasks,
        next_task   => \&start_tasks,
        task_result => \&handle_task_result,
        task_done   => \&handle_task_done,
        task_debug  => \&handle_task_debug,
        sig_child   => \&sig_child,
    }
);

# Start as many tasks as needed so that the number of tasks is no more
# than MAX_CONCURRENT_TASKS.  Every wheel event is accompanied by the
# wheel's ID.  This function saves each wheel by its ID so it can be
# referred to when its events are handled.
# Wheel::Run's Program may be a code reference.  Here it's called via
# a short anonymous sub so we can pass in parameters.

sub start_tasks {
    my ($kernel, $heap) = @_[KERNEL, HEAP];
    print "start_tasks\n";
    while (keys(%{$heap->{task}}) < MAX_CONCURRENT_TASKS) {
        my $next_task = get_task();
        last unless defined $next_task;
        print "Starting task for $next_task...\n";
        my $task = POE::Wheel::Run->new(
            Program      => sub { do_stuff($next_task) },
            StdoutFilter => POE::Filter::Reference->new(),
            StdoutEvent  => "task_result",
            StderrEvent  => "task_debug",
            CloseEvent   => "task_done",
            );
        $heap->{task}->{$task->ID} = $task;
        $kernel->sig_child($task->PID, "sig_child");
    }
}

my $i = 1;

sub get_task {
    my $task = "job$i";
    $i++;
    return $task;
}


# This function is not a POE function!  It is a plain sub that will be
# run in a forked off child.  It uses POE::Filter::Reference so that
# it can return arbitrary information.  All POE filters can be used by
# themselves, but their parameters and return values are always list
# references.

sub do_stuff {
    binmode(STDOUT);    # Required for this to work on MSWin32
    my $task   = shift;
    my $filter = POE::Filter::Reference->new();
    
    # Simulate a long, blocking task.
    sleep(rand 5);
    
    # Generate a bogus result.  Note that this result will be passed by
    # reference back to the parent process via POE::Filter::Reference.
    my %result = (
        task   => $task,
        status => "seems ok to me",
        );
    
    # Generate some output via the filter.  Note the strange use of list
    # references.
    my $output = $filter->put([\%result]);
    print @$output;
}

# Handle information returned from the task.  Since we're using
# POE::Filter::Reference, the $result is however it was created in the
# child process.  In this sample, it's a hash reference.

sub handle_task_result {
    my $result = $_[ARG0];
    print "Result for $result->{task}: $result->{status}\n";
}

# Catch and display information from the child's STDERR.  This was
# useful for debugging since the child's warnings and errors were not
# being displayed otherwise.
sub handle_task_debug {
    my $result = $_[ARG0];
    print "Debug: $result\n";
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
    
    # warn "$$: Child $pid exited";
}

# Run until there are no more tasks.
$poe_kernel->run();
exit 0;
