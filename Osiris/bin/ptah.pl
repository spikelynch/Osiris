#!/usr/bin/perl

use warnings;
use strict;

=head1 NAME

ptah.pl

=head1 SYNOPSIS

    ptah.pl

=head1 DESCRIPTION

A simple daemon built with POE::Wheel::Run which monitors the Osiris users'
working directories for incoming jobs, starts Isis processes with the 
commands and parameters stored in the jobs, and updates the status of the
jobs when the commands are completed.

=head1 CONFIGURATION

Requires the following environment variables:

=over 4

=item OSIRIS_LIB - location of the Osiris modules

=item OSIRIS_PTAHLOG - a Log::Log4perl configuration file

=item OSIRIS_WORKING - location of the Osiris working directory

=item ISISROOT - base directory of the Isis installation

=back

=cut


sub POE::Kernel::ASSERT_DEFAULT () { 1 };
use POE qw(Wheel::Run);

my @ENVARS = qw(OSIRIS_LIB
                OSIRIS_PTAHLOG
                OSIRIS_WORKING
                ISISROOT);



my $missing = 0;

for my $ev ( @ENVARS ) {
	if( !$ENV{$ev} ) {
		warn("Missing environment variable $ev\n");
		$missing = 1;
	}
}

if( $missing ) {
	die("One or more missing environment variables.\n");
}
    


use lib $ENV{OSIRIS_LIB};

use Data::Dumper;
use Log::Log4perl;
#use YAML::XS;

Log::Log4perl::init($ENV{OSIRIS_PTAHLOG});

my $ISIS_DIR = "$ENV{ISISROOT}/bin/xml";

use Osiris::User;
use Osiris::Job;

my $MAX_TASKS = $ENV{OSIRIS_MAXTASKS} || 10;

=head1 OVERVIEW

Ptah maintains two queues:

=over 4

=item $heap->{users} - list of users

=item $heap->{jobs} - list of new jobs

=back

The primary state handlers are as follows:

=over 4

=item scan_users: build a list of users

=item scan_jobs: scan each user's joblist and build a queue of new jobs

=item run_jobs: pull jobs off the queue and start them

=back

=cut


my $WORKING_DIR = $ENV{OSIRIS_WORKING};


my $log = Log::Log4perl->get_logger('ptah');


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
    fatal       => \&fatal,
    _stop       => \&stop_ptah,
  }
);

=head1 HANDLERS

=over 4


=item initialise($kernel, $heap)

Sets the job and user queues to empty, calls scan_users.

=cut


sub initialise {
    my ( $kernel, $heap ) = @_[KERNEL, HEAP];

    $log->info("[initialise]");

    $heap->{jobs} = [];
    $heap->{users} = [];
    $kernel->yield('scan_users');
}



=item scan_users($kernel, $heap, $state, $sender, @caller)

Event handler called when the job queue and user queues are both
empty.  Scans the working directory for user dirs and initialises
Osiris::User objects for them.

If it finds at least one job, calls scan_jobs.

If it finds nothing, it calls itself on a delay.

=cut


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
            basedir => $WORKING_DIR,
            isisdir => $ISIS_DIR
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

=item scan_jobs($kernel, $heap, $state, $sender, @caller)

Event handler called when the job queue is empty.  It shifts the next
user off the user queue and scans their job list for new jobs.

If it finds at least one job, calls run_jobs

If there is no next user, it calls scan_users.

=cut


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


=item run_jobs($kernel, $heap, $state, $sender, @caller)

Pulls items off the job queue until either

=over 4

=item (a) $MAX_TASKS is reached, in which case it does nothing (when a
running job is finished it will call run_jobs again); or

=item (b) there are no more jobs, in which case it calls scan_jobs to
 get more jobs from the next user.

=back

=cut

sub run_jobs {
    my ( $kernel, $heap, $state, $sender, @caller ) = 
        @_[KERNEL, HEAP, STATE, SENDER, CALLER_FILE, CALLER_LINE, CALLER_STATE];

    $log->debug("___[run_jobs]");
    $log->debug("    state = $state");
    $log->debug("    sender = $sender");
    $log->debug("    caller = " . join(', ', @caller));
    
    $log->debug("heap jobs = " . join(', ', $heap->{jobs}));
    $log->debug("running jobs " . scalar(keys %{$heap->{running}}));
    CAPACITY: while ( keys(%{$heap->{running}}) < $MAX_TASKS ) {
       
        my $job = shift @{$heap->{jobs}};
        last CAPACITY unless defined $job;

        $log->debug("Running job $job->{id}");
        
        my $command = $job->command;
        if( !$command ) {
            $heap->{error} = "Job->command returned nothing";
            $kernel->yield('fatal');
        }
        $log->debug("Marking job status 'processing'");
        $job->set_status(status => 'processing') || do {
            $log->error("Error setting job status");
            die;
        };
        $log->debug("Starting job for user $job->{user}{id}");
        $log->debug("Command string: " . join(' ', @$command));
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
        $log->info("Launched task " . $task->ID . " with pid " . $task->PID);
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


=item fatal($kernel, $heap, $state, $sender, @caller)

Called in the event of a fatal error - the working directory can't be
scanned or something like that.

=cut


sub fatal {
    my ( $kernel, $heap, $state, $sender, @caller ) = 
        @_[KERNEL, HEAP, STATE, SENDER, CALLER_FILE, CALLER_LINE, CALLER_STATE];

    $log->debug("___[fatal]");
    $log->debug("    state = $state");
    $log->debug("    sender = $sender");
    $log->debug("    caller = " . join(', ', @caller));

    $log->error("Fatal error: $heap->{error}");
}


=item stop_ptah($kernel, $heap, $state, $sender)

Stop state

=cut

sub stop_ptah {
    my ( $kernel, $heap, $state, $sender ) = 
        @_[KERNEL, HEAP, STATE, SENDER];

    $log->info("___[_stop_ptah]");
    $log->debug("    state = $state");
    $log->debug("    sender = $sender");
    print "End.\n";
}


=item handle_task_result($output, $wid)

Handle information returned from the task.  Since we're using
POE::Filter::Reference, the $result is however it was created in the
child process.  In this sample, it's a hash reference.

=cut

sub handle_task_result {
    my ( $output, $wid ) = @_[ARG0, ARG1];
    print ">>>stdout $wid>>> $output\n";
}

=item handle_task_debug($output, $wid)

Catch and display information from the child's STDERR.  This was
useful for debugging since the child's warnings and errors were not
being displayed otherwise.

=cut

sub handle_task_debug {
    my ( $output, $wid ) = @_[ARG0, ARG1];
    print "stdout $wid $output\n";
}

=item handle_task_done($kernel, $heap, $task_id)

When a task is finished, call scan_jobs

=cut

sub handle_task_done {
  my ($kernel, $heap, $task_id) = @_[KERNEL, HEAP, ARG0];


  $kernel->yield("scan_jobs");
}


=item sig_child($heap, $sig, $pid, $exit_val)

Detect the CHLD signal as each of our children exits.


=cut

sub sig_child {
    my ($heap, $sig, $pid, $exit_val) = @_[HEAP, ARG0, ARG1, ARG2];

    $log->info("sig_child caught for PID $pid");

    my $wid = $heap->{pid_to_wid}{$pid};


    if( !$wid ) {
        $log->error("Child $pid has no corresponding wheel ID");
    } else {
        $log->debug("Wheel id =  $wid");
        my $job = $heap->{running}{$wid}{job};
        $log->debug("Job from POE heap = $job $job->{id}");
        delete $heap->{running}{$wid};
        
        if( $exit_val ) {
            # There was an error: should do more to interpret this
            $log->debug("Job $job->{id} returned error ($exit_val)");
            $job->set_status(status => "error");
        } else {
            $log->debug("Setting job $job->{id} status to 'done'");
            $job->set_status(status => "done");
        } 
    }
}


=back

=cut 

$poe_kernel->run();
exit 0;

