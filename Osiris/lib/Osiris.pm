package Osiris;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;

use XML::Simple;

use JSON;

use Data::Dumper;

use Osiris::App;
use Osiris::Job;
use Osiris::User;
use Osiris::AAF;



=head1 NAME

Osiris

=head1 DESCRIPTION

Dancer interface to the Isis planetary imaging toolkit

=head1 VARIABLES

=over 4

=item $VERSION - release name and number

=item $toc - Isis table of contents - hash by command name

=item $cats - Isis apps as a hash by category

=item $extra_form - optional extra form for the job page

=item $extra_fields - list of field names for the extra form

=item $user - Osiris::User if there's a current user session

=item $jobshash - user's jobs as a hashref by job ID

=item $jobs - user's jobs as an arrayref

=back

=cut


our $VERSION = '0.2 Hor-Aha';

my $conf = config;

my ( $toc, $cats ) = load_toc(%$conf);

my ( $extra_form, $extra_fields ) = undef;

if( $conf->{extras} ) {
    ( $extra_form, $extra_fields ) = load_extras($conf->{extras});
}

my ( $user, $jobshash, $jobs );

=head1 HOOKS

=over 4

=item before

The 'before' hook checks if there is a user session active.  If there
isn't, it tests to see if this request is part of the authentication process.
If it's not, it redirects the user to either the AAF login URL, or, if
we are running in 'fake_AAF' mode, to the fake AAF login page.

To make things simpler, a route is part of the authentication process iff
it starts with '/auth'.

If there is a session and user, we set up the $user, $jobs and $jobshash
global variables, as they are used in every other page.

If the user can't be created, destroy the session and go back to the login page

=cut

hook 'before' => sub {
    
    if (! session('user') && request->path_info !~ m{^/auth}) {
        request->path_info('/auth/login');
    } elsif ( session('user') ) {
        my $atts = session('aaf');
        if( !$atts ) {
            error("No AAF atts");
        }
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
            redirect kludge_uri_for('/auth/login');
        }
        $jobshash = $user->jobs(reload => 1);
        $jobs = [];
        for my $id ( sort { $b <=> $a } keys %$jobshash ) {
            push @$jobs, $jobshash->{$id};
        }
    }
};

=back

=head1 ROUTES

Dancer routes, defined by a method ('get', 'post' or 'ajax') and a path.

=head2 Authentication

=over 4

=item get /auth/login

Authentication page. If the config variable 'aafmode' is set to 'test',
will automatically authenticate with a fake account.

Template: login.tt

=cut

get '/auth/login' => sub {

    my $target = $conf->{aaf}{url};
    my $fake = 0;
    if( $conf->{aafmode} eq 'test' ) {
        $target = kludge_uri_for('/auth/fakeaaf');
        $fake = 1;
    }

    template 'login', {
        fake => $fake,
        title => 'Log In',
        login_url => $target
    };
};



=item post /auth/aaf

The endpoint for AAF RapidConnect authentication. 

Adapted from https://gist.github.com/bradleybeddoes/6154072

See https://rapid.aaf.edu.au/developers for full details.

This is the callback endpoint: after users authenticate via AAF, an
encrypted JSON web token is POSTed to this URL.

The 'is_fake' param is used to test this with a fake JSON we generated
ourselves.

=cut


post '/auth/aaf' => sub {
    my $jwt = params->{assertion};
    my $fake = params->{is_fake};

    my $aafcf;

    if( $fake ) {
        $aafcf = $conf->{aaftest};
    } else {
        $aafcf = $conf->{aaf};
    }

    if( !$jwt ) {
        send_error("System error", 500);
    }

    my $oaaf = Osiris::AAF->new( config => $aafcf );
    
    my $claims = $oaaf->decode(jwt => $jwt);

    if( $claims ) {
        if( my $attributes = $oaaf->verify(claims => $claims) ) {
            if( my $user_id = $oaaf->user_id(attributes => $attributes) ) {
                debug("Got user id $user_id");
                session aaf => $attributes;
                session jwt => $jwt;
                session user => $user_id;

                if( $conf->{aafmode} eq 'test' ) {
                    debug("In local test mode: show user info");
                    redirect kludge_uri_for('/auth/showaaf');
                } else {
                    redirect kludge_uri_for('/');
                }
            } else {
                template 'error' => {
                    title => 'Error',
                    error => 'Authentication failed.'
                };
            }
        } else {
            warn("AAF JWT authentication failed");
            send_error(403, "Not allowed");
        }
    } else {
        warn("AAF JWT decryption failed");
        send_error(403, "Not allowed");
    }
};


=item get /auth/fakeaff

This is a URL for preliminary testing of AAF, before we send our
endpoint for registration.  It encodes a JWT from the config values,
which will definitely match when it gets to the auth endpoint.

=cut

get '/auth/fakeaaf' => sub {

    if( $conf->{aafmode} ne 'test' ) {
        redirect $conf->{aaf}{url};
    }
    my $test_conf = $conf->{aaftest};

    my $oaaf = Osiris::AAF->new(config => $test_conf);

    my $time = time;

    my $claims = {
        iss => $test_conf->{iss},
        aud => $test_conf->{aud},
        nbf => $time - 1000000,
        exp => $time + 1000000,
        jti => 'FAKEJTI' . $time,
        $test_conf->{attributes} => $conf->{aaftestatts}
    };

    my $jwt = $oaaf->encode(claims => $claims);
    debug("Encoded claims as jwt ", $jwt);

    template 'fake_aaf' => {
        jwt => $jwt,
        aaf_endpoint => '/auth/aaf'
    }
};


=item get /auth/showaff

Show the fake AAF details.

=cut


get '/auth/showaaf' => sub {
    my $atts = session('aaf');
    template 'fake_aaf' => {
        user => $user->{name},
        aaf_user => $atts
    };
};



=item get /auth/logout

Destroy the current session and redirect to the login page

=cut


get '/auth/logout' => sub {
    session->destroy;
    redirect kludge_uri_for('/auth/login');
};




=back

=head2 Jobs

=over 4

=item get /

The home page.  Shows a list of the user's jobs, or a 'getting started'
message if they have not yet created any.

=cut

get '/' => sub {

    if( @$jobs ) {

        template 'jobs' => {
            title => 'My jobs',
            user => $user->{name},
            jobs => $jobs,
        };
    } else {
        template 'getting_started' => {
            title => 'Getting Started',
            user => $user->{name}, 
        };
    }
};


=item get job/$id

Display details of job $id

=cut

get '/job/:id' => sub {
    
    my $id = param('id');
    my $job = $jobshash->{$id};

    if( ! $job ) {
        error("Warning: job $id not found!");
        forward '/';
    } else {
        
        $job->load_xml;

        my $command = $job->command;
        $command = join(' ', @$command);
        my $dir = $job->working_dir;
        $command =~ s/$dir//g;

        $job->{app} = get_app(name => $job->{appname});

        my $vars =  {
            title => "Job: " . $job->label, 
            user => $user->{name},
            job => $job,
            command => $command,
            files => $job->files,
            jobs => $jobs
        };

        if( $extra_form ) {
            $vars->{extras} = $extra_form->groups;
            for my $group ( @{$vars->{extras}} ) {
                for my $param ( @{$group->{parameters}} ) {
                    my $name = $param->{name};
                    $param->{default} = $job->{extras}{$name};
                }
            }

            $vars->{publish_url} = kludge_uri_for('/job/' . $id);
            $vars->{javascripts} = [ 'app', 'guards' ];
        }

        template 'job' => $vars;
    }
};


=item get job/$id/files/$file 

Passes through the specified file from a job.  Note: this should probably
be implemented differently, as pushing big files through Dancer isn't the
best way to do this.

=cut

get '/job/:id/files/:file' => sub {

    my $id = param('id');

    my $job = $jobshash->{$id};
    if( ! $job ) {
        forward '/jobs';
    } else {
        my $file = param('file');
        my $path = $job->working_dir(file => $file);
        if( -f $path ) {
            send_file($path, system_path => 1);
        } else {
            send_error('Not found', 404);
        }
    }
};
    


=item get /files

Returns a list of files

=cut


get '/files' => sub {

    template 'files' => {
        user => $user->{name},
        javascripts => [ 'files' ],
        jobs => $jobs
    };
};


=item ajax /jobs/:ext

Ajax handler which returns a list of all files matching an extension
pattern, as a JSON data structure like:

    { jobid => { inputs => [ files, ... ], outputs => [ files, ... ] } }

The extensions should be passed in as a list delimited by semicolons,
for eg 'cub;qub' matches *.cub and *.qub files (with case folding)

=cut

ajax '/jobs' => sub { 
    my $list = browser_files();
    to_json($list);
};


ajax '/jobs/:ext' => sub {
    my $ext = param('ext');
    my $list = browser_files($ext);
    to_json($list);
};

=item ajax /files/:id

Returns a JSON object with all the files for a given job

=cut

ajax '/files/:id' => sub {

    my $id = param('id');
    my $job = $jobshash->{$id};

    if( ! $job ) {
        send_error("Not found", 404);
    } else {
        
        $job->load_xml;
        $job->{app} = get_app(name => $job->{appname});

        my $files = $job->files;

        to_json($files);
    }
};

=back

=head2 Browsing and Searching

=over 4

=item get /browse/:by

Top-level browsing route.  'by' can either be 'category' or 'mission'.

Displays a page with all the categories or missions.

=cut

get '/browse/:by' => sub {

    my $by = param('by');
    if( $cats->{$by} ) {
        template 'browse' => {
            title => "Apps by $by",
            user => $user->{name},
            jobs => $jobs,
            browseby => $by,
            browse => $cats->{$by}
        };
    } else {
        forward '/';
    }       
};


=item get /browse/:by/:class

List all the programs in a specific category or mission

=cut

get '/browse/:by/:class' => sub {

	my $by = param('by');
	my $class = param('class');
	if( my $apps = $cats->{$by}{$class} ) {
		template 'browse_apps' => {
            title => "Apps by $by / $class",
            user => $user->{name}, 
            jobs => $jobs,
			browseby => $by,
			class => $class,
			apps => $apps
		};
	} else {
        forward "/browse/$by";
	}
};


=item get /search?q=$query

Search for an app (in app names and descriptions) and return a list.

=cut

get '/search' => sub {

    my $search = param('q');

    if( $search ) {
        my $results = search_toc(search => $search);
        template 'search' => {
            user => $user->{name},
            title => 'Search results',
            jobs => $jobs,
            search => $search,
            results => $results,
        };
    } else {
        forward('/');
    }
};


=back

=head2 Starting and viewing jobs

=over 4

=item get /app/:app

Displays the web form for the app.

=cut

get '/app/:app' => sub {
    
	my $appname = param('app');

	if( $toc->{$appname} ) {
		my $app = Osiris::App->new(
			dir => $conf->{isisdir},
			app => $appname,
			brief => $toc->{$appname}
		);

        if( !$app ) {
            template 'error' => {
                title => 'Error',
                user => $user->{name},
                jobs => $jobs,
                error => "System error: couldn't initialise app form for $appname."
            };
        } else {
            
            my @p = $app->params;
        
            if( !@p ) {
                template 'error' => {
                    title => 'Error',
                    user => $user->{name},
                    jobs => $jobs,
                    error => "The app '$appname' can't be operated via the web."
                };
            } else {
                
                my $guards = $app->guards;
                for my $p ( keys %$guards ) {
                    $guards->{$p} = encode_json($guards->{$p});
                }
                
                # NOTE: took uri_for out of url and back_url
                
                template 'app' => {
                    title => $appname,
                    user => $user->{name},
                    url => kludge_uri_for('/app/' . $app->name),
                    back_url => kludge_uri_for('/'),
                    jobs => $jobs,
                    javascripts => [ 'app', 'guards', 'files' ],
                    app => $app->name,
                    brief => $app->brief,
                    form => $app->form,
                    guards => $guards,
                    description => $app->description
                };
            }
        }
    } else {
        forward('/');
    }
};


=item /post/:app

Starts a job: takes the parameters posted and creates a job file with them

=cut


post '/app/:name' => sub {

	my $name = param('name');

	if( !$toc->{$name} ) {
        send_error('Not found', 404);
    }

	my $app = Osiris::App->new(
        dir => $conf->{isisdir},
        app => $name,
        brief => $toc->{$name}
		);

    my $job = $user->create_job(app => $app);

    # input_files sets the input file parameters.

    my $params = input_files(
        app => $app,
        job => $job,
        user => $user
        );

    # The rest can be copied directly from the form.

    for my $p ( $app->params ) {
        if( !$params->{$p} ) {
            $params->{$p} = param($p);
        }
    }

    # Check for extra extension fields for output parameters

    for my $p ( $app->output_params ) {
        my $p_ext = $p . '_ext';
        if( my $ext = param($p_ext) ) {
            $params->{$p_ext} = $ext;
        }
    }


    if( !$job->add_parameters(parameters => $params) ) {
        # invalid parameters: 
    }

    if( $user->write_job(job => $job) ) {

        forward "/job/$job->{id}", {}, { method => 'GET' };
    } else {
        error("Couldn't write job");
        template 'error' => {
            title => 'Job error',
            user => $user->{name},
            jobs => $jobs,
            error => "Couldn't start job."
        };
    }
        
};


=item post /job/:id

Accept the extra form fields and write them into the job file.  This
is how the system accepts publication metadata.

The contents of the extra form fields is controlled by
views/metadata_form.xml, which is in the same format as the Isis
application XML files.

=cut

post '/job/:id' => sub {

    my $id = param('id');
    my $job = $jobshash->{$id};

    if( ! $job ) {
        error("Warning: job $id not found!");
        forward '/';
    } else {
        
        $job->load_xml;
    
        my $extras = {};
        for my $field ( @$extra_fields ) {
            $extras->{$field} = param($field);
        }

        $job->add_extras(%$extras);

        if( $user->write_job(job => $job) ) {
            debug("Forwarding to /job/$job->{id}");
            forward "/job/$job->{id}", {}, { method => 'GET' };
        } else {
            error("Couldn't write job");
            template 'error' => {
                title => 'Job error',
                user => $user->{name},
                jobs => $jobs,
                error => "Couldn't submit job for publishing"
            };
        }
    }
        
};

=back

=head1 METHODS

=over 4

=item input_files(%params)

This method takes the parameters submitted when creating a job and processes
each of the input file parameters.

=over 4

=item job

=item app

=item user

=item params

=back

If the user has submitted a file to upload, it copies it into the working
directory for the job.

Otherwise, if they have selected a file from a previous job, it builds a
path to that file.

If neither of these works, logs an error and returns the error template.

=cut


sub input_files {
    my %params = @_;
    
    my $job = $params{job};
    my $app = $params{app};
    my $user = $params{user};
    my $par = $params{params};

    my $p = {};
    my $parents = {};

    PARAM: for my $u ( $app->input_params ) {
        my $existing_file = param($u . '_alt');
        my $upload = upload($u);
        my $bands = param($u . '_bands');

        if( !$upload && !$existing_file ) {
            warn("Neither are defined, returning undef\n");
            next PARAM;
        }
        if( $existing_file && !$upload ) {
            debug("$u: using existing file $existing_file\n");
            my ( $type, $job, $file ) = split('/', $existing_file);
            $p->{$u} = '../' . $job . '/' . $file;
            debug("Setting input parameter $u: $p->{$u}\n");
            if( $type eq 'output' ) {
                $parents->{$u} = $job;
            }
        } else {
            my $filename = $upload->filename;
            my $to_file = $job->working_dir(file => $filename);

            if( ! $upload->copy_to($to_file) ) {
                error("Couldn't copy upload to $filename");
                template 'error' => {
                    user => $user->{name}, 
                    error => "Couldn't create Osiris::Job"
                };
            } else {
                debug("Copied to $to_file\n");
                $p->{$u} = $filename;
                debug("Setting input parameter $u: $p->{$u}\n");
            }
        }
        
        if( $bands ) {
            $p->{$u} .= '+' . $bands;
        }
    }

    for my $pp ( keys %$parents ) {
        $p->{_annotations}{$pp}{parent} = $parents->{$pp};
    }

    return $p;
}


=item get_app(name => $name);

Looks up the table of contents by app name and returns an Osiris::App
object

=cut


sub get_app {
    my %params = @_;

    my $name = $params{name};

	if( $toc->{$name} ) {
		my $app = Osiris::App->new(
			dir => $conf->{isisdir},
			app => $name,
			brief => $toc->{$name}
		);
        return $app;
    } else {
        return undef;
    }
}


=item load_toc(isisdir => $id, isistoc => $it)

Loads and parses the applicationTOC.xml file, builds the table of contents.

=cut


sub load_toc {
	my %params = @_;
	
	if( !$params{isisdir} || !$params{isistoc} ) {
		die("Need isisdir and isistoc");
	}
	
	my $toc = join('/', $params{isisdir}, $params{isistoc});	
	
	my $xml = XMLin($toc) || die ("Couldn't parse $toc");
	
	my $apps = $xml->{application};
	my $browse = {
		category => {},
		mission => {}
	};

	for my $app ( keys %$apps ) {
		my $cats = $apps->{$app}{category};
		my $desc = $apps->{$app}{brief};
		$desc =~ s/^\s+//g;
		$desc =~ s/\s+$//g;

		for my $what ( qw(category mission) ) {
			my $key = $what . 'Item';
			if ( my $items = $cats->{$key} ) {
				if( !ref($items) ) {
					$items = [ $items ];
				}
				for my $item ( @$items ) {
					$browse->{$what}{$item}{$app} = $desc;
				}
			}
		}
		$apps->{$app} = $desc;
	}

	return ( $apps, $browse );
}


=item search_toc(search => $search);

Search the table of contents.  Returns a list of results as
   
  { app => $app, description => $desc }

hashes in alphabetical order.

=cut

sub search_toc {
    my %params = @_;
    
    my $search = $params{search};
    my $results = {};

    my @toks = split(/ +/, $search);
    my $re = '(' . join('|', @toks) . ')';
    $re = qr/$re/i;

    for my $app ( keys %$toc ) {
        if( $app =~ $re || $toc->{$app} =~ $re ) {
            $results->{$app} = 1;
        }
    }

    my $r = [];

    for my $app ( sort keys %$results ) {
        push @$r, {
            app => $app,
            description => $toc->{$app}
        }; 
    }
    if( @$r ) {
        return $r;
    } else {
        return undef;
    }

}


=item load_extras($xml)

load the 'extras' form, which we're using to collect metadata to push
out to the RDC

=cut

sub load_extras {
    my ( $xml ) = @_;
    
    my $extras = Osiris::Form->new(xml => $xml);
    
    if( !$extras ) {
        error("Error initialising extras file $xml"); 
        return undef;
    }
    
    if( !$extras->parse ) {
        error("Error parsing extras file $xml");
        return undef;
    }
    
    debug("Loaded extras file $xml");

    my $api = $extras->groups;

    my @fields = ();

    for my $group ( @$api ) {
        for my $param ( @{$group->{parameters}} ) {
            push @fields, $param->{name};
        }
    }
    return ( $extras, \@fields );
}


=item kludge_uri_for($path)

Hack to get around a bug in the deployment layer which was defaulting
the protocol to http:// when we want it to be https://

If the config variable 'forceprotocol', it forces it.

=cut



sub kludge_uri_for {
    my ( $path ) = @_;
    
    my $uri = uri_for($path);
    if( $conf->{forceprotocol} ) {
        $uri =~ s/^https?/$conf->{forceprotocol}/;
        debug("Forced protocol: $path => $uri");
    }

    return $uri;
}


=item browser_files($exts)

Backend for the ajax jobs/ method.  $exts is a semicolon-delimited set
of extensions.  If $exts is empty, returns all input and output files

=cut

sub browser_files {
    my ( $ext ) = @_;

    my $ajobs = {};
    
    my $exts_re = undef;

    if( $ext ) {
        my $exts = join('|', split(';', $ext));
        $exts_re = qr/\.($exts)$/io;
    }

    for my $id ( sort { $b <=> $a } keys %$jobshash ) {
        my $job = $jobshash->{$id};
        my $files = {};
        my $any = 0;
        for my $c ( 'from', 'to' ) {
            if( $job->{$c} ) {
                for my $file ( split(/ /, $job->{$c}) ) {
                    if( !$exts_re || $file =~ /$exts_re/ ) {
                        push @{$files->{$c}}, $file;
                        $any = 1;
                    }
                }
            }
        }
        if( $any ) {
            $ajobs->{$id} = {
                id => $id,
                appname => $jobshash->{$id}->{appname},
                label => $jobshash->{$id}->label,
            };
            if( $files->{from} ) {
                $ajobs->{$id}{inputs} = $files->{from};
            }
            if( $files->{to} ) {
                $ajobs->{$id}{outputs} = $files->{to};
            }
        }
    }

    return $ajobs;
}


true;


=back

=cut

