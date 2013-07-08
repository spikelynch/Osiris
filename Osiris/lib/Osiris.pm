package Osiris;

use Dancer ':syntax';
use XML::Simple;

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


# /  a list of app categories and missions

get '/' => sub {
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
		template 'app' => {
            user => $user->{id}, 
            javascripts => [ 'app' ],
			app => $app->name,
			brief => $app->brief,
			form => $app->form,
			description => $app->description,
		};
	} else {
		send_error("Not found", 404);
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

    for my $p ( $app->param_fields ) {
        $params->{$p} = param($p);
    }

    for my $u ( $app->upload_fields ) {
        $uploads->{$u} = upload($u);
    }

    my $job = $user->create_job(
        app => $app,
        parameters => $params,
        uploads => $uploads
    );

    
    if( !$job ) {
        debug("in error clause");
        template 'error' => {
            user => $user->{id}, 
            error => "Couldn't create Osiris::Job"
        }
    } else {
        debug("Got job = $job");
        template 'testjob' => {
            user => $user->{id}, 
            job => $job->xml
        };
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



sub get_user {
    return Osiris::User->new(
        id => session->{user},
        basedir => $conf->{workingdir}
        );
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
