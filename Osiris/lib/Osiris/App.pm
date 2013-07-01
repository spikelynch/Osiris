package Osiris::App;

use strict;

use XML::Twig;


sub new {
	my ( $class, %params ) = @_;
	
	my $self = {};
	bless $self, $class;
	
	$self->{app} = $params{app};
	$self->{dir} = $params{dir};	
	$self->{brief} = $params{brief};
	
	return $self;
}


=item form()

Returns an HTML form built from this app's <groups> tag.

=cut

sub form {
	my ( $self ) = @_;
	
	if( !$self->{api} ) {
		$self->parse_api;
	}
	
	
	warn("entering form for $self->{name}");

	my $html = "<form name=\"$self->{name}\">\n";
	
	for my $group ( @{$self->{api}{groups}} ) {
		$html .= $self->form_group($group);
	}
	
	$html .= "</form>";
	
	return $html;
}


=item form_group($group)

HTML version of a <group> element

=cut

sub form_group {
	my ( $self, $group ) = @_;
	
	warn("<div> for group $group->{name}");
	
	my $html =<<EOHTML;
<div id="grp_$group->{name}">
EOHTML
	
	for my $parameter ( @{$group->{parameters}} ) {
		$html .= $self->form_parameter($parameter);
	}
	
	$html .= "</div>";
	return $html;
	
}


=item form_parameter($parm)

Render a single parameter field

=cut

sub form_parameter {
	my ( $self, $parameter ) = @_;
	
	warn("Parameter $parameter->{name}");
	
	my $input;
	
	if( $parameter->{list} ) {
		$input = $self->form_list($parameter);
	} else {
		$input = $self->form_text($parameter);
	}
	
	return<<EOHTML;
<div class="parameter">
<span class="label">$parameter->{name}</span>
$input<br />
<span class="brief">$parameter->{brief}
</div>
EOHTML
}



=item form_text($parameter)

Text input item

=cut

sub form_text {
	my ( $self, $parameter ) = @_;
	
	return <<EOHTML;
<input class="isisform"
	   name="$parameter->{name}"
	   type="text"
	   size="40"
	   value="$parameter->{default}[0]" />
EOHTML

}


=item form_list($parameter)

Drop-down list input item

=cut

sub form_list {
	my ( $self, $parameter ) = @_;
	
	my @options = ();
	
	for my $item ( @{$parameter->{list}} ) {
		my $selected = '';
		if( $item->{value} eq $parameter->{default}[0] ) {
			$selected = ' selected';
		} 
		push @options, <<EOHTML;
<option value="$item->{value}"$selected>$_->{value} ($_->{brief})</option>
EOHTML
	}
	
	my $html = "<select name=\"$parameter->{name}\">\n";
	$html .= join("\n", @options);
	$html .= "</select>\n";
	
	return $html;
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
			brief => 		sub { $self->xml_field($_) 		},
			description => 	sub { $self->xml_field($_) 		},
			category => 	sub { $self->xml_category($_) },
			group =>        sub { $self->xml_group($_)		}
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
		push @{$group->{parameters}}, $self->xml_parameter($pelt);
	}
	
	push @{$self->{api}{groups}}, $group;
}


=item xml_parameter($elt)

Top-level method for parsing parameters - the more complicated
child elements are farmed out to their own methods.

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
				$parameter->{$_} = [ $child->children_text ];
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
				last SWITCH;
			};
			
			# default: copy the text of the element
			
			$parameter->{$_} = $child->text;
		}
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
	
	if( $elt->att('inclusive') =~ /yes|true/ ) {
		$minimax->{inclusive} = 1;
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
	
	


1;
