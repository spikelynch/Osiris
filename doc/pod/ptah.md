# NAME

ptah.pl

# SYNOPSIS

    ptah.pl

# DESCRIPTION

A simple daemon built with POE::Wheel::Run which monitors the Osiris users'
working directories for incoming jobs, starts Isis processes with the 
commands and parameters stored in the jobs, and updates the status of the
jobs when the commands are completed.

# CONFIGURATION

Requires the following environment variables:

- OSIRIS\_LIB - location of the Osiris modules
- OSIRIS\_PTAHLOG - a Log::Log4perl configuration file
- OSIRIS\_WORKING - location of the Osiris working directory
- ISISROOT - base directory of the Isis installation

# OVERVIEW

Ptah maintains two queues:

- $heap->{users} - list of users
- $heap->{jobs} - list of new jobs

The primary state handlers are as follows:

- scan\_users: build a list of users
- scan\_jobs: scan each user's joblist and build a queue of new jobs
- run\_jobs: pull jobs off the queue and start them

# HANDLERS



- initialise($kernel, $heap)

    Sets the job and user queues to empty, calls scan\_users.

- scan\_users($kernel, $heap, $state, $sender, @caller)

    Event handler called when the job queue and user queues are both
    empty.  Scans the working directory for user dirs and initialises
    Osiris::User objects for them.

    If it finds at least one job, calls scan\_jobs.

    If it finds nothing, it calls itself on a delay.

- scan\_jobs($kernel, $heap, $state, $sender, @caller)

    Event handler called when the job queue is empty.  It shifts the next
    user off the user queue and scans their job list for new jobs.

    If it finds at least one job, calls run\_jobs

    If there is no next user, it calls scan\_users.

- run\_jobs($kernel, $heap, $state, $sender, @caller)

    Pulls items off the job queue until either

    - (a) $MAX\_TASKS is reached, in which case it does nothing (when a
    running job is finished it will call run\_jobs again); or
    - (b) there are no more jobs, in which case it calls scan\_jobs to
     get more jobs from the next user.

- fatal($kernel, $heap, $state, $sender, @caller)

    Called in the event of a fatal error - the working directory can't be
    scanned or something like that.

- stop\_ptah($kernel, $heap, $state, $sender)

    Stop state

- handle\_task\_result($output, $wid)

    Handle information returned from the task.  Since we're using
    POE::Filter::Reference, the $result is however it was created in the
    child process.  In this sample, it's a hash reference.

- handle\_task\_debug($output, $wid)

    Catch and display information from the child's STDERR.  This was
    useful for debugging since the child's warnings and errors were not
    being displayed otherwise.

- handle\_task\_done($kernel, $heap, $task\_id)

    When a task is finished, call scan\_jobs

- sig\_child($heap, $sig, $pid, $exit\_val)

    Detect the CHLD signal as each of our children exits.


