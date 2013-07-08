package Osiris::App;

use strict;

use XML::Twig;
use Log::Log4perl;

=head NAME

Osiris::App

=head DESCRIPTION

A class representing an Isis app.  Has the code for parsing the Isis
XML specifying the App's API, for generating a job file, and
(eventually) for generating the command line to be run.

=cut


sub new {
	my ( $class, %params ) = @_;
	
	my $self = {};
	bless $self, $class;
	
	$self->{app} = $params{app};
	$self->{dir} = $params{dir};	
	$self->{brief} = $params{brief};
    

    $self->{log} = Log::Log4perl->get_logger($class);


	return $self;
}



=item name()

Return the app's name

=cut

sub name {
	my ( $self ) = @_;
	
	return $self->{app};
}


=item brief() 

Return the app's brief description

=cut

sub brief {
	my ( $self ) = @_;
	
	return $self->{brief};
}



=item description() 

Return the app's full description, which may contain HTML

=cut

sub description {
	my ( $self ) = @_;
	
	if( ! $self->{api} ) {
		$self->parse_api;
	}
	return $self->{api}{description};
}



=item form()

Returns this app's form as a data structure which can be used to
fill out the web form in views/app.tt. 
=cut

sub form {
	my ( $self ) = @_;
	
	if( !$self->{api} ) {
		$self->parse_api;
	}
	
	return $self->{api}{groups};
	
}



=item param_fields

Return a list of all the app's parameters which are not 
file uploads.

=cut
 
sub param_fields {
	my ( $self ) = @_;

	if( !$self->{api} ) {
		$self->parse_api;
	}
	
	return @{$self->{param_fields}};
}


=item upload_fields

Return a list of all of the app's file upload parameters

=cut

sub upload_fields {
	my ( $self ) = @_;

	if( !$self->{api} ) {
		$self->parse_api;
	}
	
	return @{$self->{upload_fields}};
}





=item parse_api()

Parses this app's XML file

=cut


sub parse_api {
	my ( $self ) = @_;
	
	my $xml_file = "$self->{dir}/$self->{app}.xml";
	
	$self->{api} = {};
	
	my $tw = XML::Twig->new(
		twig_handlers => {
			'application/brief' => sub { $self->xml_field($_)    },
			'application/description' => sub { $self->xml_field($_) 	  },
			'application/category' => 	sub { $self->xml_category($_) },
			group =>        sub { $self->xml_group($_)	  }
		}
	);
	
	$tw->parsefile($xml_file);
	
	return $self->{api};
} 



=item xml_field($elt)

Copy an element's inner_xml into the api using its tagname as
the field name

=cut


sub xml_field {
	my ( $self, $elt ) = @_;
	
	my $tag = $elt->tag;
	$self->{api}{$tag} = $elt->inner_xml;
}

=item xml_category($elt)

Parses the <category> element

=cut

sub xml_category {
	my ( $self, $elt ) = @_;
	
	$self->{categories} = {};
	$self->{missions} = {};
	
	for my $celt ( $elt->children ) {
		my $cat = $celt->text;
		if( $celt->tag eq 'categoryItem' ) {
			$self->{categories}{$cat} = 1
		} else {
			$self->{missions}{$cat} = 1;
		}
	}
}

=item xml_group($elt)

Parses a <group> element.  Each app has a <groups> element,
containing one or more <group>s, each of which has one or more
<parameters>.  This routine calls xml_parameter on each of the
child parameters, stores it in a group hashref, then appends
the group hashref to 

=cut

sub xml_group {
	my ( $self, $elt ) = @_;
	
	my $group = {
		name => $elt->att('name'),
		parameters => []
	};
	
	for my $pelt ( $elt->children('parameter') ) {
		my $param = $self->xml_parameter($pelt);
		push @{$group->{parameters}}, $param;
		if( $param->{field_type} eq 'input_file_field' ) {
			push @{$self->{upload_fields}}, $param->{name};
		} else {
			push @{$self->{param_fields}}, $param->{name};
		}
	}
	
	push @{$self->{api}{groups}}, $group;
}


=item xml_parameter($elt)

Top-level method for parsing parameters - the more complicated
child elements are farmed out to their own methods.

NOTE: in the ISIS schema, the tags default, greaterThan,
lessThan and notEqual contain one or more <item> tags, within
which are the actual values.  In the current release, there are
no apps which have more than one <item> tag in any of these 
elements, so this code just grabs the first item.

=cut


sub xml_parameter {
	my ( $self, $elt ) = @_;
	
	my $parameter = {
		name => $elt->att('name')
	};
	
	for my $child ( $elt->children ) {
		my $tag = $child->tag;
		
		SWITCH: {
			$_ = $tag;
			
			/description/ && do {
				$parameter->{description} = $child->inner_xml;
				last SWITCH;
			};
			
			/default|greaterThan|lessThan|notEqual|exclusions|inclusions/ && do {
				$parameter->{$_} = $child->first_child_trimmed_text; #see POD above
				last SWITCH;
			};
			
			/count/ && do {
				$parameter->{$_} = $child->att('size');
				last SWITCH;
			};
			
			/minimum|maximum/ && do {
				$parameter->{$_} = $self->xml_minimax($child);
				last SWITCH;
			};
			
			/list/ && do {
				$parameter->{$_} = $self->xml_list($child);
				$parameter->{is_list} = 1;
				last SWITCH;
			};
			
			# default: copy the text of the element
			
			$parameter->{$_} = $child->trimmed_text;
		}
	}
	if( exists $parameter->{fileMode} ) {
		$parameter->{is_file} = $parameter->{fileMode};
		if( $parameter->{fileMode} eq 'input' ) {
			$parameter->{field_type} = 'input_file_field';
		} else {
			$parameter->{field_type} = 'output_file_field';
            $parameter->{extension} = substr($parameter->{filter}, 1);
		}
	} elsif( $parameter->{is_list} ) {
		$parameter->{field_type} = 'list_field';
	} elsif( $parameter->{type} eq 'boolean' ) {
		$parameter->{field_type} = 'boolean_field';
		$parameter->{default} = $self->xml_fix_boolean(
            raw => $parameter->{default}
            );
	} else {
		$parameter->{field_type} = 'text_field';
	}
	return $parameter;
}


=item xml_minimax($elt)

Parse a <minimum> or <maximum> element

=cut

sub xml_minimax {
	my ( $self, $elt ) = @_;
	
	my $minimax = {
		value => $elt->text,
		inclusive => 0
	};
	
	if( my $inc = $elt->att('inclusive') ) {

		if( $inc =~ /yes|true/ ) {
			$minimax->{inclusive} = 1;
		}
	}
	return $minimax;
}


=item xml_list($elt)

Parse a <list> element, which gives a list with options and other
fiddle

=cut


sub xml_list {
	my ( $self, $elt ) = @_;
	
	my $options = [];
	
	for my $oelt ( $elt->children('option')  ) {
		my $option = {
			value => $oelt->att('value'),
			brief => $oelt->first_child_text('brief')
		};
		if( my $delt = $oelt->first_child('description') ) {
			$option->{description} = $delt->inner_xml;
		}
		if( my $exelt = $oelt->first_child('exclusions') ) {
			$option->{exclusions} = [ $exelt->children_text ];
		}
		if( my $inelt = $oelt->first_child('inclusions') ) {
			$option->{inclusions} = [ $inelt->children_text ];
		}
		push @$options, $option;
	}
	return $options;
}


=item xml_helpers($elt)

Parse a <helpers> element, which holds 1+ helper functions

=cut

sub xml_helpers {
	my ( $self, $elt ) = @_;
	
	my $helpers = [];
	
	for my $helt ( $elt->children('helper') ) {
		my $helper = {
			name => $helt->att('name')
		};
		$helper->{function} = $helt->child_text('function');
		$helper->{brief}    = $helt->child_text('brief');
		if( my $delt = $helt->first_child('description') ) {
			$helper->{description} = $delt->inner_xml;
		}
		push @$helpers, $helper;
	}
	
	return $helpers;
}
	
=item xml_fix_boolean(raw => $bool)
	
Standardise the boolean values found in the XML to either
'true' or 'false'

=cut

sub xml_fix_boolean {
	my ( $self, %params ) = @_;
	
	my $raw = $params{raw};
	
	if( $raw =~ /true|yes/i ) {
		return 'true';
	} else {
		return 'false';
	}
}


1;
