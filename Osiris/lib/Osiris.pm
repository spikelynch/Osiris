package Osiris;

use Dancer ':syntax';
use XML::Simple;

use Osiris::App;
use Osiris::Job;

=head NAME

Osiris

=head DESCRIPTION

Dancer interface to the Isis planetary imaging toolkit

=cut


our $VERSION = '0.1';

my $conf = config;

my ( $toc, $cats ) = load_toc(%$conf);


# /  a list of app categories and missions

get '/' => sub {
    template 'index' => { browse => $cats };
};

# /browse -  a list of applications for a category or mission

get '/browse/:by/:class' => sub {
	my $by = param('by');
	my $class = param('class');
	if( my $apps = $cats->{$by}{$class} ) {
		template 'browse' => {
			browseby => $by,
			class => $class,
			apps => $apps
		};
	} else {
		template 'index' => { toc => $cats }
	}
};


# /app - the web form for an app


get '/app/:name' => sub {
	my $name = param('name');
	if( $toc->{$name} ) {
		my $app = Osiris::App->new(
			dir => $conf->{isisdir},
			app => $name,
			brief => $toc->{$name}
		);
		template 'app' => {
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
	my $name = param('name');

	if( !$toc->{$name} ) {
        send_error('Not found', 404);
    }

    my $files = {};
    my $params = {};

	my $app = Osiris::App->new(
        dir => $conf->{isisdir},
        app => $name,
        brief => $toc->{$name}
		);

    for my $p ( $app->param_fields ) {
        $params->{$p} = param($p);
    }

    for my $u ( $app->upload_fields ) {
        $files->{$u} = upload($u);
    }

    my $job = Osiris::Job->new(
        dir => $conf->{workingdir},
        app => $app,
        parameters => $params,
        files => $files
    );

#    my $job = $user->create_job(
#        app => $app,
#        parameters => $params,
#        files => $files
#    );

    
    if( !$job ) {
        template 'index' => {
            browse => $cats,
            error => "Something went wrong"
        }
    }
    
    if( $job->write ) {
#        forward "/jobs/" . $job->{id};
        template 'testjob' => { job => $job->xml };
    } else {
        send_error('System error', 500);
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
