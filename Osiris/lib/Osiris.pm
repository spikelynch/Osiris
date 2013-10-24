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



=head NAME

Osiris

=head DESCRIPTION

Dancer interface to the Isis planetary imaging toolkit

=head VARIABLES

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

=head HOOKS

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


# AAF JWT code adapted from https://gist.github.com/bradleybeddoes/6154072
#
# See https://rapid.aaf.edu.au/developers for full details.
#
# This is the callback endpoint: after users authenticate via AAF, an
# encrypted JSON web token is POSTed to this URL.
#
# the 'is_fake' param is used to test this with a fake JSON we generated
# ourselves.,

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


# this is a URL for preliminary testing of AAF, before we send 
# our endpoint for registration.  It encodes a JWT from the config
# values, which will definitely match when it gets to the auth
# endpoint.


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

=item get /auth/showaaf

=cut


get '/auth/showaaf' => sub {
    my $atts = session('aaf');
    template 'fake_aaf' => {
        user => $user->{name},
        aaf_user => $atts
    };
};


# this is the old authentication

# post '/login' => sub {
    
#     Validate the username and password they supplied
#     if (params->{user} eq $fakeuser && params->{pass} eq $fakeuser ) {
#         debug("Logged in as $fakeuser");
#         session user => params->{user};
#         redirect params->{path} || '/';
#     } else {
#         redirect '/login?failed=1';
#     }
# };




get '/auth/logout' => sub {
    session->destroy;
    redirect kludge_uri_for('/auth/login');
};









###### Routes for starting jobs, looking at the job list and 
#      accessing results

# Default page: current user's job list

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



# job/$id - view job details

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
            debug("Filling in extra fields ");
            for my $group ( @{$vars->{extras}} ) {
                for my $param ( @{$group->{parameters}} ) {
                    my $name = $param->{name};
                    debug("Field = $name = $job->{extras}{$name}");
                    $param->{default} = $job->{extras}{$name};
                }
            }

            $vars->{publish_url} = kludge_uri_for('/job/' . $id);
            $vars->{javascripts} = [ 'app', 'guards' ];
        }

        template 'job' => $vars;
    }
};


# job/$id/files/$file - pass through a link to a file

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
    

get '/files' => sub {

    template 'files' => {
        user => $user->{name},
        javascripts => [ 'files' ],
        jobs => $jobs
    };
};




# Ajax handler for browsing a user's working directory.  Returns a 
# JSON object with files broken down by input, output and other.

ajax '/jobs' => sub {
    
    my $ajobs = {};

    for my $id ( keys %$jobshash ) {
        $ajobs->{$id} = {
            id => $id,
            appname => $jobshash->{$id}->{appname},
            label => $jobshash->{$id}->label
        }
    }

    to_json($ajobs);
};



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



###### Routes for browsing/searching apps
#

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





# /browse -  a list of applications for a category or mission

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


# /app - the web form for an app
# URLs can be of the form app/[mission or category]/app
#                      or app/$app



get '/app/:app' => sub {
    
	my $appname = param('app');
	if( $toc->{$appname} ) {
		my $app = Osiris::App->new(
			dir => $conf->{isisdir},
			app => $appname,
			brief => $toc->{$appname}
		);

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
    } else {
        forward('/');
    }
};



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




# post /app - start a job.

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

    warn("Job params: " . Dumper($params));

    if( !$job->add_parameters(parameters => $params) ) {
        # invalid parameters: 
    }

    if( $user->write_job(job => $job) ) {
        debug("Forwarding to /job/$job->{id}");
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


# post to job/n -> accept the extra form fields and write them 
# into the job file.  In this version, this is the publication
# metadata



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



# input_files - does the juggling around file uploads v existing
# files on the system


sub input_files {
    my %params = @_;
    
    my $job = $params{job};
    my $app = $params{app};
    my $user = $params{user};
    my $par = $params{params};

    my $p = {};
    my $parents = {};

    warn("Input params:");

    PARAM: for my $u ( $app->input_params ) {
        my $existing_file = param($u . '_alt');
        my $upload = upload($u);

        warn("Input param $u");
        warn("upload = $upload existing = $existing_file\n");

        if( !$upload && !$existing_file ) {
            warn("Neither are defined, returning undef\n");
            next PARAM;
        }
        if( $existing_file && !$upload ) {
            warn("$u: using existing file $existing_file\n");
            my ( $type, $job, $file ) = split('/', $existing_file);
            $p->{$u} = '../' . $job . '/' . $file;
            warn("Setting input parameter $u: $p->{$u}\n");
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
                warn("Copied to $to_file\n");
                $p->{$u} = $filename;
                warn("Setting input parameter $u: $p->{$u}\n");
            }
        }
    }

    for my $pp ( keys %$parents ) {
        $p->{_annotations}{$pp}{parent} = $parents->{$pp};
    }

    return $p;
}


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


# search the table of contents.  Returns a list of results as
# { app => $app, description => $desc } hashes. Alphabetical order.

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

# load the 'extras' form, which we're using to collect metadata
# to push out to the RDC


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



sub kludge_uri_for {
    my ( $path ) = @_;
    
    my $uri = uri_for($path);
    if( $conf->{forceprotocol} ) {
        $uri =~ s/^https?/$conf->{forceprotocol}/;
        debug("Forced protocol: $path => $uri");
    }

    return $uri;
}


true;
