package Osiris::Form;

use strict;

use XML::Twig;
use Log::Log4perl;
use Data::Dumper;
use JSON;

use Log::Log4perl;



my $CLUSIONED = {
    inclusions => 'included',
    exclusions => 'excluded'
};
    


=head NAME

Osiris::Form

=head DESCRIPTION


Class for parsing ISIS forms - used both on the App and Job pages.

=head API

Here is the structure of the form API:

form = ARRAYREF of groups:
    { 
        name => GROUPNAME
        parameters => ARRAYREF of parameters:
            [
                {
                    name => NAME
                    field_type => FIELD_TYPE
                    type => DATA_TYPE
                    description => DESCRIPTION
                    default => DEFAULT
                    ... (more) ...
                },                  
                ...
            ]
    }
    ...

FIELD_TYPE is one of text_field
                     textarea_field
                     list_field
                     boolean_field
                     input_file_field 
                     output_file_field

TYPE is one of string/integer/double/boolean

Note that textarea_fields are not in the Isis XML but I've added them
to support textareas in the additional metadata fields.

=cut

sub new {
    my ( $class, %params ) = @_;
    
    my $self = {};
    bless $self, $class;

    $self->{log} = Log::Log4perl->get_logger($class);


    if ( !$params{xml} ) {
        $self->{log}->error("No XML file for $class");
        return undef;
    }

    if( ! -f $params{xml} ) {
        $self->{log}->error("File not found $params{xml} in $class");
    }

    $self->{xml_file} = $params{xml};

    return $self;
}

# a bunch of accessor functions 

sub description {
    my ( $self ) = @_;

    return $self->{api}{description}
}

sub groups {
    my ( $self ) = @_;

    return $self->{api}{groups}
}


sub params {
    my ( $self ) = @_;
    
    return $self->_aref('param_fields');
}

sub input_params {
    my ( $self ) = @_;
    
    return $self->_aref('input_fields');
}

sub output_params {
    my ( $self ) = @_;
    
    return $self->_aref('output_fields');
}

sub _aref {
    my ( $self, $field ) = @_;

    if( $self->{$field} ) {
        return @{$self->{$field}};
    } else {
        return ();
    }
}



sub param {
    my ( $self, %params ) = @_;

    my $p = $params{param};

    return $self->{paramshash}{$p};
}
    

sub guards {
    my ( $self ) = @_;

    return $self->{api}{guards};
}


=item parse()

Parses the XML file and returns an API structure which can 
be passed to the HTML templates

=cut


sub parse {
	my ( $self ) = @_;
	
	$self->{api} = {};
    $self->{api}{all_params} = [];
    $self->{paramshash} = {};
	
	my $tw = XML::Twig->new(
		twig_handlers => {
			'application/brief' => sub { $self->xml_field($_)    },
			'application/description' => sub { $self->xml_field($_) 	  },
			'application/category' => 	sub { $self->xml_category($_) },
			group =>        sub { $self->xml_group($_)	  }
		}
	);
	
    eval {
        $tw->parsefile($self->{xml_file});
    };

    if( $@ ) {
        $self->{log}->error("Fatal error parsing $self->{xml_file}: $@");
        return undef;
    }
    
    # Shortcut to the file fields
    
    my ( $files ) = grep { $_->{name} eq 'Files' } @{$self->{api}{groups}};
    if( $files ) {
        for my $p ( @{$files->{parameters}} ) {
            $self->{api}{file_fields}{$p->{name}} = $p;
        }
    }

    my $guards = {};

    for my $group ( @{$self->{api}{groups}} ) {
        for my $p ( @{$group->{parameters}} ) {
            if( my $guard = $self->make_guard(parameter => $p) ) {
                $guards->{$p->{name}} = $guard;
            }
        }
    }

    # record clusion guards against the fields they in/exclude too

    for my $pname ( keys %$guards ) {
        for my $clusion ( qw(inclusions exclusions) ) {
            my $ch = $guards->{$pname}{$clusion};
            my $clusioned = $CLUSIONED->{$clusion} || die("No reverse $clusion");
            for my $value ( keys %$ch ) {
                for my $cp ( @{$ch->{$value}} ) {
                    $guards->{$cp}{$clusioned}{$pname}{$value} = 1;
                }
            }
        }
    }

    $self->{api}{guards} = $guards;
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
        push @{$self->{param_fields}}, $param->{name};
        $self->{paramshash}{$param->{name}} = $param;
		if( $param->{field_type} eq 'input_file_field' ) {
			push @{$self->{input_fields}}, $param->{name};
		} else {
            if( $param->{field_type} eq 'output_file_field' ) {
                push @{$self->{output_fields}}, $param->{name};
            }
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
	} elsif( $parameter->{type} eq 'textarea' ) {
        $parameter->{field_type} = 'textarea_field';
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

To apply the guards to an job, call $job->assert_guards() (NOT YET)

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

    if( $p->{field_type} eq 'input_file_field' ) {
        $guards->{input_file} = 1;
        if( $p->{filter} ) {
            $guards->{filepattern} = $self->_make_filter(
                filter => $p->{filter}
                );
            $guards->{label} = $p->{filter};
        }
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
