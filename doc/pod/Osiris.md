# NAME

Osiris

# DESCRIPTION

Dancer interface to the Isis planetary imaging toolkit

# VARIABLES

- $VERSION - release name and number
- $toc - Isis table of contents - hash by command name
- $cats - Isis apps as a hash by category
- $extra\_form - optional extra form for the job page
- $extra\_fields - list of field names for the extra form
- $user - Osiris::User if there's a current user session
- $jobshash - user's jobs as a hashref by job ID
- $jobs - user's jobs as an arrayref

# HOOKS

- before

    The 'before' hook checks if there is a user session active.  If there
    isn't, it tests to see if this request is part of the authentication process.
    If it's not, it redirects the user to either the AAF login URL, or, if
    we are running in 'fake\_AAF' mode, to the fake AAF login page.

    To make things simpler, a route is part of the authentication process iff
    it starts with '/auth'.

    If there is a session and user, we set up the $user, $jobs and $jobshash
    global variables, as they are used in every other page.

    If the user can't be created, destroy the session and go back to the login page

# ROUTES

Dancer routes, defined by a method ('get', 'post' or 'ajax') and a path.

## Authentication

- get /auth/login

    Authentication page. If the config variable 'aafmode' is set to 'test',
    will automatically authenticate with a fake account.

    Template: login.tt

- post /auth/aaf

    The endpoint for AAF RapidConnect authentication. 

    Adapted from https://gist.github.com/bradleybeddoes/6154072

    See https://rapid.aaf.edu.au/developers for full details.

    This is the callback endpoint: after users authenticate via AAF, an
    encrypted JSON web token is POSTed to this URL.

    The 'is\_fake' param is used to test this with a fake JSON we generated
    ourselves.

- get /auth/fakeaff

    This is a URL for preliminary testing of AAF, before we send our
    endpoint for registration.  It encodes a JWT from the config values,
    which will definitely match when it gets to the auth endpoint.

- get /auth/showaff

    Show the fake AAF details.

- get /auth/logout

    Destroy the current session and redirect to the login page

## Jobs

- get /

    The home page.  Shows a list of the user's jobs, or a 'getting started'
    message if they have not yet created any.

- get job/$id

    Display details of job $id

- get job/$id/files/$file 

    Passes through the specified file from a job.  Note: this should probably
    be implemented differently, as pushing big files through Dancer isn't the
    best way to do this.

- get /files

    Returns a list of files

- ajax /jobs/:ext

    Ajax handler which returns a list of all files matching an extension
    pattern, as a JSON data structure like:

        { jobid => { inputs => [ files, ... ], outputs => [ files, ... ] } }

    The extensions should be passed in as a list delimited by semicolons,
    for eg 'cub;qub' matches \*.cub and \*.qub files (with case folding)

- ajax /files/:id

    Returns a JSON object with all the files for a given job

## Browsing and Searching

- get /browse/:by

    Top-level browsing route.  'by' can either be 'category' or 'mission'.

    Displays a page with all the categories or missions.

- get /browse/:by/:class

    List all the programs in a specific category or mission

- get /search?q=$query

    Search for an app (in app names and descriptions) and return a list.

## Starting and viewing jobs

- get /app/:app

    Displays the web form for the app.

- /post/:app

    Starts a job: takes the parameters posted and creates a job file with them

- post /job/:id

    Accept the extra form fields and write them into the job file.  This
    is how the system accepts publication metadata.

    The contents of the extra form fields is controlled by
    views/metadata\_form.xml, which is in the same format as the Isis
    application XML files.

# METHODS

- input\_files(%params)

    This method takes the parameters submitted when creating a job and processes
    each of the input file parameters.

    - job
    - app
    - user
    - params

    If the user has submitted a file to upload, it copies it into the working
    directory for the job.

    Otherwise, if they have selected a file from a previous job, it builds a
    path to that file.

    If neither of these works, logs an error and returns the error template.

- get\_app(name => $name);

    Looks up the table of contents by app name and returns an Osiris::App
    object

- load\_toc(isisdir => $id, isistoc => $it)

    Loads and parses the applicationTOC.xml file, builds the table of contents.

- search\_toc(search => $search);

    Search the table of contents.  Returns a list of results as
       

        { app => $app, description => $desc }

    hashes in alphabetical order.

- load\_extras($xml)

    load the 'extras' form, which we're using to collect metadata to push
    out to the RDC

- kludge\_uri\_for($path)

    Hack to get around a bug in the deployment layer which was defaulting
    the protocol to http:// when we want it to be https://

    If the config variable 'forceprotocol', it forces it.

- browser\_files($exts)

    Backend for the ajax jobs/ method.  $exts is a semicolon-delimited set
    of extensions.  If $exts is empty, returns all input and output files
