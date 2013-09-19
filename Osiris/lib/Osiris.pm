package Osiris;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;

use XML::Simple;
use JSON;
use Data::Dumper;

use Osiris::App;
use Osiris::Job;
use Osiris::User;



=head NAME

Osiris

=head DESCRIPTION

Dancer interface to the Isis planetary imaging toolkit

=cut


our $VERSION = '0.1 Narmer';

my $conf = config;

my ( $toc, $cats ) = load_toc(%$conf);

my $fakeuser = $conf->{fakeuser};

# The before hook: if there's no session, redirect the user to the
# login page.

# If there is a user, get the Osiris::User object and load the joblist
# because these are used in every route.

my ( $user, $jobshash, $jobs );

hook 'before' => sub {
    if (! session('user') && request->path_info !~ m{^/login}) {
        var requested_path => request->path_info;
        request->path_info('/login');
    } else {
        $user = Osiris::User->new(
            id => session('user'),
            basedir => $conf->{workingdir}
        );
        $jobshash = $user->jobs(reload => 1);
        $jobs = [];
        for my $id ( sort keys %$jobshash ) {
            push $jobs, $jobshash->{$id};
        }
    }   
};

get '/login' => sub {
    template 'login', { title => 'Log In', path => vars->{requested_path} };
};

post '/login' => sub {
    
    # Validate the username and password they supplied
    if (params->{user} eq $fakeuser && params->{pass} eq $fakeuser ) {
        debug("Logged in as $fakeuser");
        session user => params->{user};
        redirect params->{path} || '/';
    } else {
        redirect '/login?failed=1';
    }
};

get '/logout' => sub {
    session->destroy;
    redirect '/login';
};


###### Routes for starting jobs, looking at the job list and 
#      accessing results

# Default page: current user's job list

get '/' => sub {

    if( @$jobs ) {

        template 'jobs' => {
            title => 'My jobs',
            user => $user->{id},
            jobs => $jobs,
        };
    } else {
        template 'getting_started' => {
            title => 'Getting Started',
            user => $user->{id}
        };
    }
};



# job/$id - details for a job

get '/job/:id' => sub {
    
    my $id = param('id');
    my $job = $jobshash->{$id};

    if( ! $job ) {
        forward '/jobs';
    } else {
        
        $job->load_xml;
        my $vars =  {
            title => "Job $id - $job->{appname}", 
            user => $user->{id},
            job => $job,
            jobs => $jobs
        };
        my $command = $job->command;
        $vars->{command} = join(' ', @$command);
        my $dir = $job->working_dir;
        $vars->{command} =~ s/$dir//g;
        $job->{app} = get_app(name => $job->{appname});
        $vars->{files} = $job->files;
        debug("Job fles = " . Dumper({files => $vars->{files}}));
        $vars->{title} = 'Job ' . $job->{id};
        template job => $vars
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

    template files => {
        user => $user,
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
            user => $user->{id},
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
            user => $user->{id}, 
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
    
	my $name = param('app');
	if( $toc->{$name} ) {
		my $app = Osiris::App->new(
			dir => $conf->{isisdir},
			app => $name,
			brief => $toc->{$name}
		);

        my @p = $app->params;
        
        if( !@p ) {
            template 'error' => {
                title => 'Error',
                user => $user->{id},
                jobs => $jobs,
                error => "The app '$name' can't be operated via the web."
            };
        } else {

            my $guards = $app->guards;
            for my $p ( keys %$guards ) {
                $guards->{$p} = encode_json($guards->{$p});
            }
            
            #my $debugmsg = "Guards: \n" . Dumper({guards => $guards});
            
            
            template 'app' => {
                title => $name,
                user => $user->{id},
                jobs => $jobs,
                javascripts => [ 'app', 'guards', 'files' ],
                app => $app->name,
                brief => $app->brief,
                form => $app->form,
                guards => $guards,
                description => $app->description,
                #           debugmsg => $debugmsg,
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
            user => $user,
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
#    my $user = get_user();
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
            user => $user->{id},
            jobs => $jobs,
            error => "Couldn't start job."
        };
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

    for my $u ( $app->input_params ) {
        my $existing_file = param($u . '_alt');
        my $upload = upload($u);
        if( !$upload && !$existing_file ) {
            return undef;
        }
        if( $existing_file && !$upload ) {
            debug("$u: using existing file $existing_file");
            my ( $type, $job, $file ) = split('/', $existing_file);
            $p->{$u} = '../' . $job . '/' . $file;
            debug("Result $type, $job, $file, = $p->{$u}");
            if( $type eq 'output' ) {
                $parents->{$u} = $job;
            }
        } else {
            my $filename = $upload->filename;
            my $to_file = $job->working_dir(file => $filename);

            if( ! $upload->copy_to($to_file) ) {
                error("Couldn't copy upload to $filename");
                template 'error' => {
                    user => $user->{id}, 
                    error => "Couldn't create Osiris::Job"
                };
            } else {
                debug("Copied to $to_file");
                debug("Setting input parameter as $filename");
                $p->{$u} = $filename;
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






true;
