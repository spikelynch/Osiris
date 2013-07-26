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


our $VERSION = '0.1';

my $conf = config;

my ( $toc, $cats ) = load_toc(%$conf);

my $fakeuser = $conf->{fakeuser};

# login stuff snarfed from Dancer::Cookbook and hit with a hammer

hook 'before' => sub {
    if (! session('user') && request->path_info !~ m{^/login}) {
        var requested_path => request->path_info;
        request->path_info('/login');
    }
};

get '/login' => sub {
    template 'login', { path => vars->{requested_path} };
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

###### Routes for browsing/searching apps
#
# /  a list of app categories and missions

get '/browse' => sub {
    my $user = get_user();
    template 'index' => { user => $user->{id}, browse => $cats };
};

# /browse -  a list of applications for a category or mission

get '/browse/:by/:class' => sub {
    my $user = get_user();
	my $by = param('by');
	my $class = param('class');
	if( my $apps = $cats->{$by}{$class} ) {
		template 'browse' => {
            user => $user->{id}, 
			browseby => $by,
			class => $class,
			apps => $apps
		};
	} else {
		template 'index' => {
            user => $user->{id}, 
            toc => $cats
        }
	}
};


# /app - the web form for an app


get '/app/:name' => sub {
    my $user = get_user();
	my $name = param('name');
	if( $toc->{$name} ) {
		my $app = Osiris::App->new(
			dir => $conf->{isisdir},
			app => $name,
			brief => $toc->{$name}
		);

        my @p = $app->params;
        my $guards = $app->guards;
        for my $p ( keys %$guards ) {
            $guards->{$p} = encode_json($guards->{$p});
        }

        my $debugmsg = "Guards: \n" . Dumper({guards => $guards});

		template 'app' => {
            user => $user->{id}, 
            javascripts => [ 'app', 'guards', 'files' ],
			app => $app->name,
			brief => $app->brief,
			form => $app->form,
            guards => $guards,
			description => $app->description,
            debugmsg => $debugmsg,
		};
	} else {
		send_error("Not found", 404);
	}
};



#
#
#get '/apps/search/:str' => sub {
#	template 'search';
#};
#
#
#
#




###### Routes for starting jobs, looking at the job list and 
#      accessing results

# Default page: current user's job list

get '/' => sub {
    my $user = get_user();
    
    my $jobhash = $user->jobs(reload => 1);

    my $jobs = [];

    if( $jobhash ) {
        for my $id ( sort keys %$jobhash ) {
            push @$jobs, $jobhash->{$id};
        }
    }

    template jobs => {
        user => $user->{id},
        jobs => $jobs
    };

};



# job/$id - details for a job

get '/job/:id' => sub {
    my $user = get_user();
    
    my $id = param('id');
    my $jobhash = $user->jobs(reload => 1);
    my $job = $jobhash->{$id};
    if( ! $job ) {
        forward '/jobs';
    } else {
        
        $job->load_xml;
        my $vars =  {
            user => $user->{id},
            job => $job,
        };
        my $command = $job->command;
        $vars->{command} = join(' ', @$command);
        my $dir = $job->working_dir;
        $vars->{command} =~ s/$dir//g;
        $job->{app} = get_app(name => $job->{appname});
        $vars->{files} = $job->files;
        template job => $vars
    }
};


# job/$id/files/$file - pass through a link to a file

get '/job/:id/files/:file' => sub {
    my $user = get_user();
    my $id = param('id');
    my $jobhash = $user->jobs(reload => 1);
    my $job = $jobhash->{$id};
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
    my $user = get_user();
    my $jobs = $user->jobs(reload => 1);

    template files => {
        javascripts => [ 'files' ],
        jobs => $jobs
    };
};




# Ajax handler for browsing a user's working directory.  Returns a 
# JSON object with files broken down by input, output and other.

ajax '/jobs' => sub {
    my $user = get_user();
    my $joblist = $user->jobs(reload => 1);
    
    my $jobs = {};

    for my $id ( keys %$joblist ) {
        $jobs->{$id} = { appname => $joblist->{$id}->{appname} }
    };


    to_json($jobs);
};



ajax '/files/:id' => sub {
    my $user = get_user();
    my $id = param('id');
    my $jobhash = $user->jobs(reload => 1);
    my $job = $jobhash->{$id};

    if( ! $job ) {
        send_error("Not found", 404);
    } else {
        
        $job->load_xml;
        $job->{app} = get_app(name => $job->{appname});

        my $files = $job->files;

        debug("files: ", $files);

        to_json($files);
    }
};



# post /app - start a job.

post '/app/:name' => sub {
    my $user = get_user();
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

    debug('params ', $params);

    $job->add_parameters(parameters => $params);

    if( $user->write_job(job => $job) ) {
        
        template 'job' => {
            user => $user->{id},
            job => $job 
        }
    } else {
        error("Couldn't write job");
        template 'error' => {
            user => $user->{id}, 
            error => "Couldn't create Osiris::Job"
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
                $p->{$u} = $to_file;
            }
        }
    }

    for my $pp ( keys %$parents ) {
        $p->{_annotations}{$pp}{parent} = $parents->{$pp};
    }

    return $p;
}







sub get_user {
    return Osiris::User->new(
        id => session->{user},
        basedir => $conf->{workingdir}
        );
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






true;
