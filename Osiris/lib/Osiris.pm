package Osiris;

use Dancer ':syntax';
use XML::Twig;


=head NAME

Osiris

=head DESCRIPTION

Dancer interface to the Isis planetary imaging toolkit

=cut


our $VERSION = '0.1';

my $conf = read_config();

my $apps = {};

my $browse = {
	category => {},
	mission => {}
};

load_apps();

# Index: a list of app categories and missions

get '/' => sub {
    template 'index' => { toc => $browse };
};

# Category: a list of all applications in a category

get '/cat/:cat' => sub {
	my $cat = params('cat');
	if( $browse->{category}{$cat} ) {
		template 'browse' => {
			apps => $browse->{category}{$cat},
			category => $cat,
		};
	} else {
		template 'index' => { toc => $browse }
	}
};

# Missions: a list of all applications in a mission

get '/mission/:mission' => sub {
	my $mission = params('mission');
	if( $browse->{mission}{$mission} ) {
		template 'browse' => {
			apps => $browse->{mission}{$mission},
			mission => params('mission'),
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
