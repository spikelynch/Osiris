package Osiris;

use Dancer ':syntax';
use XML::Simple;


=head NAME

Osiris

=head DESCRIPTION

Dancer interface to the Isis planetary imaging toolkit

=cut


our $VERSION = '0.1';

my $conf = config;

my $apps = {};

my $browse = {
	category => {},
	mission => {}
};

load_apps();


# Index: a list of app categories and missions

get '/' => sub {
    template 'index' => {
    	categories => $browse->{category},
    	missions => $browse->{mission}
    };
};

# Browse: a list of applications for a category or mission

get '/browse/:by/:class' => sub {
	my $by = param('by');
	my $class = param('class');
	if( my $apps = $browse->{$by}{$class} ) {
		template 'browse' => {
			browseby => $by,
			class => $class,
			apps => $apps
		};
	} else {
		template 'index' => { toc => $browse }
	}
};

#get '/apps/search/:str' => sub {
#	template 'search';
#};
#
#
#get '/app/:name' => sub {
#	template 
#};
#
#








sub load_apps {
	my $toc = join('/', $conf->{appdir}, $conf->{apptoc});	
	
	my $xml = XMLin($toc) || die ("Couldn't parse $toc");
	
	$apps = $xml->{application};
	$browse = {
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
	
}






true;
