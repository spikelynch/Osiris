package Osiris;

use Dancer ':syntax';
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

        my @p = $app->all_params;
        my $guards = $app->guards;
        for my $p ( keys %$guards ) {
            $guards->{$p} = encode_json($guards->{$p});
        }

        my $debugmsg = "Guards: \n" . Dumper({guards => $guards});

		template 'app' => {
            user => $user->{id}, 
            javascripts => [ 'app', 'guards' ],
			app => $app->name,
			brief => $app->brief,
			form => $app->form,
            all_params => \@p,
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
            job => $job
        };
        if( $job->{status} eq 'done' ) {
            $job->{app} = get_app(name => $job->{appname});
            $vars->{files} = $job->output_files;
        }
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
        $job->load_xml;
        if( !$job->{parameters}{$file} ) {
            forward "/jobs/$id";
        } else {
            my $filename = $job->working_dir(file => $job->{parameters}{$file});
            send_file($filename, system_path => 1);
        }
    }
};
    



# post /app - start a job.

post '/app/:name' => sub {
    my $user = get_user();
	my $name = param('name');

	if( !$toc->{$name} ) {
        send_error('Not found', 404);
    }

    my $params = {};
    my $uploads = {};

	my $app = Osiris::App->new(
        dir => $conf->{isisdir},
        app => $name,
        brief => $toc->{$name}
		);

    for my $p ( $app->params ) {
        $params->{$p} = param($p);
    }

    for my $u ( $app->upload_params ) {
        $uploads->{$u} = upload($u);
    }

    my $job = $user->create_job(
        app => $app,
        parameters => $params,
        uploads => $uploads
    );
    
    if( !$job ) {
        template 'error' => {
            user => $user->{id}, 
            error => "Couldn't create Osiris::Job"
        }
    } else {
        template 'job' => {
            user => $user->{id},
            job => $job 
        }
    }
};








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
