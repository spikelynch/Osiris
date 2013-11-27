# NAME

Osiris::User



# SYNOPSIS

    $user = Osiris::User->new(
        id => session('user'),
        name => $atts->{cn},
        atts => $atts,
        isisdir => $conf->{isisdir},
        basedir => $conf->{workingdir}
    );
    
    if( !$user ) {
        error("Couldn't create Osiris::User object");
        session->destroy;
        redirect '/auth/login';
    }
    
    my $jobshash = $user->jobs(reload => 1);



# DESCRIPTION

A class representing a user.  It maintains the user's working
directory and list of jobs and their status, and contains their login
attributes.

It's also used to create new jobs.

# METHODS

- new(%params)

    Create a new user object. Parameters as follows:

    - id - the user's identifier (a hashed AAF digest, in this case)
    - basedir - the main working dir, containing all of the user dirs
    - isisdir - the root directory of the Isis install
    - mail - the user's email
    - name - the user's screen name

    Returns undef if something goes wrong reading or creating the user's
    joblist.

- working\_dir()

    Return this user's working dir (basedir/user\_id)

- \_ensure\_working\_dir()

    Checks if the working directory exists, and tries to create it if it 
    doesn't.  If the directory exists or was created successfully, returns
    1, otherwise undef.

- jobs(\[ reload => 1 \])

    Returns the job list as a hashref of Osiris::Job objects keyed by ID.
    The jobs will only know their status and id - to parse their XML file,
    call $job->load.

    To force a reload, pass in reload => 1

- create\_job(app => $app)

    Method used by the Dancer app to create a new job for this user.
    Used to also take the uploads and parameters, but these are now added 
    separately by calling add\_parameters and add\_input\_files on the
    Job.

    Returns the Osiris::Job object if successful, undef if not.

- write\_job(job => $job)

    How the joblist and job files are updated.  Takes an Osiris::Job, calls its
    write method, and then updates the job list and tries to write that.  Returns
    the job if successful, undef if not.

- \_new\_jobid()

    Returns a new, unique job ID

- \_joblistfile()

    Full path to the joblist file.

- \_load\_joblist()

    Load the user's job list, if it exists.  Otherwise initialises the 
    {jobs} member variable to an empty hashref.

- \_load\_job($elt)

    XML::Twig handler to read a single job element

- \_save\_joblist()

    Saves the job list.

- \_save\_job()

    Returns a job as an XML element for the joblist

- update\_joblist( job => $job, status => $status )

    Public version of \_save\_joblist.  This looks the job up by id, rather
    than just updating the job object, because the job list may have been
    reloaded on the user betweentimes.

    The job can be passed as an ID or an Osiris::Job.  

    This hasn't been changed drastically from when the joblist was a textfile
    with just id and status - so it can't be used to modify any of the other
    joblist fields.  But they shouldn't change anyway.


