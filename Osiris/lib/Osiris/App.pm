package Osiris::App;

use strict;

use XML::Twig;
use Log::Log4perl;
use Data::Dumper;
use JSON;

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

=item 





=item params

Return a list of all the app's parameters which are not 
file uploads.

=cut
 
sub params {
	my ( $self ) = @_;

	if( !$self->{api} ) {
		$self->parse_api;
	}
	
	return @{$self->{param_fields}};
}


=item upload_fields

Return a list of all of the app's file upload parameters

=cut

sub upload_params {
	my ( $self ) = @_;

	if( !$self->{api} ) {
		$self->parse_api;
	}
	
	return @{$self->{upload_fields}};
}


=item all_params

Returns a list of all the form's parameters (including file uploads)

=cut

sub all_params {
    my  ( $self ) = @_;
    
    if ( !$self->{api} ) {
        $self->parse_api;
    }

#    $self->{log}->debug(Dumper({api => $self->{api}}));

    return @{$self->{api}{all_params}};
}

    


=item file_filter

Check if a parameter is a file.  If it is, returns the extension
filter (ie '*.cub');

=cut

sub file_filter {
    my ( $self, %params ) = @_;

    my $p = $params{parameter};

    if( my $field = $self->{api}{file_fields}{$p} ) {
        return $field->{filter};
    } else {
        return undef;
    }
}

=item output_files

A list of all the output file parameters for this app

=cut

sub output_files {
    my ( $self ) = @_;

    my $fields = [];

    for my $field ( sort keys %{$self->{api}{file_fields}} ) {
        if( $field->{type} eq 'output_file_field' ) {
            push @$fields, $field->{name};
        }
    }
    return $fields
} 

=item guards()

Returns all this form's guards as a hash-by-parameter name.  Used to
JSON-encode it but that happens in the web app now.

guards = {
     file: '.cub',
     text: 'int/double/string'
     mandatory: t or f
     range: { gt , gte , lt , lte }
     inclusions: { opt1: [ p1, p2, p3 ], opt2: [ p5 ] },
     exclusions: { opt4: [ p1, p2, p3 ] }
}

=cut

sub guards {
    my ( $self, %params ) = @_;

    if( !$self->{api} ) {
        $self->parse_api;
    }

    if( $self->{api}{guards} ) {
        $self->{api}{guards};
    } else {
        return '{}';
    }
}



=item parse_api()

Parses this app's XML file

=cut


sub parse_api {
	my ( $self ) = @_;
	
	my $xml_file = "$self->{dir}/$self->{app}.xml";
	
	$self->{api} = {};
    $self->{api}{all_params} = [];
	
	my $tw = XML::Twig->new(
		twig_handlers => {
			'application/brief' => sub { $self->xml_field($_)    },
			'application/description' => sub { $self->xml_field($_) 	  },
			'application/category' => 	sub { $self->xml_category($_) },
			group =>        sub { $self->xml_group($_)	  }
		}
	);
	
	$tw->parsefile($xml_file);
    
    # Shortcut to the file fields
    
    my ( $files ) = grep { $_->{name} eq 'Files' } @{$self->{api}{groups}};
    if( $files ) {
        for my $p ( @{$files->{parameters}} ) {
            $self->{api}{file_fields}{$p->{name}} = $p;
        }
    }

    $self->{api}{guards} = {};

    for my $group ( @{$self->{api}{groups}} ) {
        for my $p ( @{$group->{parameters}} ) {
            if( my $guard = $self->make_guard(parameter => $p) ) {
                $self->{api}{guards}{$p->{name}} = $guard;
            }
        }
    }

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
the group hashref to {groups}

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
        push @{$self->{api}{all_params}}, $param->{name};
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


=item make_guard(parameter => $p)

Takes one of the parameter hashes from the API and returns the guards
for this as a Perl data structure.

To fetch an app's guards as a hash by parameter, call $app->guards().

To apply the guards to an job, call $job->assert_guards();

Conversion to JSON used to be done here but now it's left to the
Dancer framework

=cut



sub make_guard {
    my ( $self, %params ) = @_;

    my $p = $params{parameter};

    my $guards = {};

    if( !$p->{default} ) {
        $guards->{mandatory} = 1;
    } else {
        $guards->{mandatory} = 0;
    }

    # only filter input files by extension, because we are automatically
    # adding the extension to output files.
    if( $p->{filter} && $p->{field_type} eq 'input_file_field' ) {
        
        $guards->{filepattern} = $self->_make_filter(filter => $p->{filter});
        $guards->{label} = $p->{filter};
    } elsif( $p->{type} =~ /integer|double|string/ ) {
        $guards->{type} = $p->{type};
        if( $p->{type} ne 'string' ) {
            $guards->{label} = $p->{type};
        }
    }

    # Silently ignoring < > guards for non-numeric types.
    # Assuming that field X can only have one of each inequality.
    # (I've checked the current (July '13) Isis and this is OK for now.)

    if( $p->{type} =~ /integer|double/ ) {

        if( $p->{greaterThan} ) {
            $guards->{gt} = $p->{greaterThan};
        }
        if( $p->{greaterThanOrEqual} ) {
            $guards->{gte} = $p->{greaterThanOrEqual}
        }
        if( $p->{lessThan} ) {
            $guards->{lt} = $p->{lessThan};
        }
        if( $p->{lessThanOrEqual} ) {
            $guards->{lte} = $p->{lessThanOrEqual}
        }
    }

    if( $p->{list} ) {
        for my $option ( @{$p->{list}} ) {
            for my $e ( qw(inclusions exclusions) ) {
                if( $option->{$e} ) {
                    $guards->{$e}{$option->{value}} = $option->{$e};
                }
            }
        }
    }
    return $guards;
}


=item _make_filter(filter => '*.cub')

Turns the content of a <filter> tag in the XML API and converts it
to a Javascript regexp, for eg:

    *.cub *.QUB

    \.(cub|QUB)$

=cut


sub _make_filter {
    my ( $self, %params ) = @_;

    my $filter = $params{filter};

    my @globs = split(/\s+/, $filter);

    my @exts = ();

    for my $glob ( @globs ) {
        if( $glob =~ /\*\.(.*)$/ ) {
            push @exts, $1;
        } else {
            $self->{log}->error("Couldn't parse filter: $filter");
        }
    }

    my $re = '\.(' . join('|', @exts) . ')$';

    return $re;
}

1;
