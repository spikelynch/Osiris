# NAME

Osiris::Job

# SYNOPSIS

    my $job = Osiris::Job->new(
        user => $user,
        app => $app,
        id => $id,
    );

    $job->set_status(status => $done);

    $job->write;

    my @files = $job->files;



# DESCRIPTION

A class representing a job - an Isis app, a set of parameters,
including one or more input files, and an output filename, and a User.

This class is used by the Dancer app to create and monitor jobs, and
by the daemon to run them.

Jobs have a status, which is stored in the user's joblist file. Takes
the following values:

- new - value at creation
- processing - set when the Isis process starts running
- done - set when the Isis process completes successfully
- error - set when the Isis process completes unsuccessfully.

NOTE: in this class, 'app' refers to an Osiris::App object, and 
'appname' refers to the object's name (the actual command line program's
name.)  When passing back a summary for the job, 'appname' is called 'app'.

All filenames are now relative to the working directory for this job.
This includes filenames used from previous jobs, which will have relative
paths like '../$OLD\_JOB\_ID/$FILENAME'

# METADATA

Each job has the following metadata fields:

- id
- status
- app
    
- user
    
- from (list of input files)
    
- to (list of output files)
    
- created (timestamp)
    
- started (timestamp)
    
- finished (timestamp)

# METHODS

- new(id => $id, dir => $dir, status => $status)

    Job objects are created by Osiris::User - either when it scans the user's
    joblist, or adds a new job via the write\_job method.

- create\_dir()

    Create this job's subdirectory in the user's working directory

- working\_dir(\[file => $file\])

    Returns the directory in which this job will be run.  If a file param is
    passed in, returns the complete path to a file in the directory.

- file\_exists(file => $relfile)

    Given a filepath relative to this job's working directory, check that
    the file exists.  (Jobs can have input files from other jobs - this 
    method needs to work for those too.)

- write()

    Writes out this job's XML

    FIXME - this has to create the parameter and file lists itself

    WARNING: this method was originally only used to create a job.  I am
    adjusting things so that it can be used to rewrite a job (to update the
    status etc) but am a bit worried that this will break a bunch of things.

- set\_status(status => $status)

    Writes this job's status to its user's job queue.  Note that this updates
    the status for this object, but refers to the job by ID when saving the
    joblist - trying to cover all bases.

    It also sets timestamps as follows:

        'processing'             => sets the 'started' timestamp
        'done' and 'error'       => set the 'finished' timestamp



    When the status is set to 'done' it also scans the working dir for
    files and updates the 'TO' field in the metadata if there is more than
    one output file

    It now rewrites the job's XML file.

- add\_parameters(parameters => \\%params)

    Does any checking or conversion required on the parameters -
    this will include parameter value checking, and making sure that
    output files don't already exist etc.

    This is now used for ALL parameters, as copying the input files
    now happens outside this object.

    The parameter '\_annotations' can be used to store notes against
    parameters.  Currently used to store 'parent' = job id from which
    an input value was derived.

- add\_extras(%params)

    Adds one or more 'extra' parameters (like publication metadata)

- timestamp()

    Returns a nicely-formatted timestamp

- summary()

    Returns a hashref of this job's details, suitable for use in a job list:

    - id
    =item created
    =item started
    =item finished
    =item status
    =item appname
    =item user
    =item from
    =item to

    TODO: parent and child jobs?

- label()

    Returns a unique label for this job - id:appname

- xml\_file()

    Generates and returns the full path to the job's XML file

- xml()

    Return the XML representation of this job

- read\_xml()

    Reads a job from the XML file in the user's working directory.

    This also creates an App object.

- load\_app()

    Load the job's App.

- command()

    Returns an arrayref of command-line arguments that Ptah (the processing
    daemon) can pass to exec.

- files()

    Returns all the files associated with this job as a hashref:

        {
            print => $PRINTCONTENTS,
            inputs => [ { file => $filename, param => $param } ]
            outputs => [ { file => $filename, [ param => $param ] } ]
        }  

    Note that there may be more than one file associated with a given
    output field (ie FILENAME.odd.cub and FILENAME.even.cub) - this routine
    tries to guess which ones match based on the job parameters.



- \_read\_print\_prt()

    Attempts to read the job's PRINT.PRT file

- \_read\_dir()

    Reads the working directory for this job and returns a hashref of
    filenames (relative to the working directory, with print.prt and the
    job xml file filtered out)
