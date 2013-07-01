use Test::More;

use strict;

use Osiris;
use Osiris::App;

my $APPDIR = '/home/mike/Isis/isis/bin/xml/';
my $APPTOC = 'applicationTOC.xml';
my $APPCATS = 'applicationCategories.xml';
my $HTMLDIR = '/home/mike/workspace/DC18C Osiris/test/html/';

my ( $toc, $cats ) = Osiris::load_toc(
	appdir => $APPDIR,
	apptoc => $APPTOC
);


for my $appname ( sort keys %$toc ) {
	my $app = Osiris::App->new(
		dir => $appdir,
		app => $appname
	);
	
	my $api = $app->parse_api;
	
	ok($api, "Parsed app $appname");

	print Dumper({$appname => $api});	
	
}
#	my $html = $app->form;
#	
#	ok($html, "Got app's HTML form");
#	
#	my $htmlfile = $HTMLDIR . $appname . ".html";
#
#	if( ok(open(HTML, ">$htmlfile"), "Writing to $htmlfile" ) {
#		print HTML, $html;
#		close HTML;
#	} else {
#		diag("Couldn't open $htmlfile $!");
#	}
}