package Osiris;

use Dancer ':syntax';
use XML::Simple;

use Osiris::App;


=head NAME

Osiris

=head DESCRIPTION

Dancer interface to the Isis planetary imaging toolkit

=cut


our $VERSION = '0.1';

my $conf = config;

my ( $toc, $cats ) = load_toc(%$conf);


# Index: a list of app categories and missions

get '/' => sub {
    template 'index' => {
    	categories => $cats->{category},
    	missions => $cats->{mission}
    };
};

# Browse: a list of applications for a category or mission

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

get '/app/:name' => sub {
	my $name = param('name');
	if( $toc->{$name} ) {
		my $app = Osiris::App->new(
			dir => $conf->{appdir},
			app => $name,
			brief => $toc->{$name}
		);
		template 'app' => {
			app => $app->name,
			brief => $app->brief,
			form => $app->form,
			description => $app->description,
		};
	} else {
		send_error("Not found", 404);
	}
};



#get '/apps/search/:str' => sub {
#	template 'search';
#};
#
#
#
#








sub load_toc {
	my %params = @_;
	
	if( !$params{appdir} || !$params{apptoc} ) {
		die("Need appdir and apptoc");
	}
	
	my $toc = join('/', $params{appdir}, $params{apptoc});	
	
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
