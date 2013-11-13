package Osiris::App;

use strict;

use Log::Log4perl;
use Data::Dumper;

use Osiris::Form;

=head NAME

Osiris::App

=head DESCRIPTION

A class representing an Isis app.  Uses Osiris::Form to parse the XML for
the web form API.

=cut


sub new {
	my ( $class, %params ) = @_;
	
	my $self = {};
	bless $self, $class;
   

	$self->{app} = $params{app};
	$self->{dir} = $params{dir};	
	$self->{brief} = $params{brief};
    

    $self->{log} = Log::Log4perl->get_logger($class);

    if( $self->read_form ) {
        return $self;
        
    } 
    
    $self->{log}->error("Couldn't create Osiris::Form object for $self->{app}");
    return undef

}


=item read_form()

Ensure that the form has been parsed, and return the Osiris::Form
object. Undef if it fails.

=cut


sub read_form {
    my ( $self ) = @_;

	if( ! $self->{form} ) {
        my $xml_file = "$self->{dir}/$self->{app}.xml";

        $self->{form} = Osiris::Form->new(
            xml => $xml_file
            ) || do {
                $self->{log}->error("Init form failed");
                return undef;
        };

        $self->{form}->parse || do {
                $self->{log}->error("Form parse failed");
                return undef;
        };
    }

    return $self->{form};
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

    if( $self->read_form ) {
        return $self->{form}->description;
    }
}



=item form()

Returns this app's form as a data structure which can be used to
fill out the web form in views/app.tt. 
=cut

sub form {
	my ( $self ) = @_;
	
    if( $self->read_form ) {
       return $self->{form}->groups;
    }
}


=item params

Return a list of all the app's parameters

=cut
 
sub params { return $_[0]->{form}->params; }


=item input_params

Return a list of all of the app's file upload parameters

=cut

sub input_params { return $_[0]->{form}->input_params; }

=item output_params

Returns a list of all of this app's output file parameter names

=cut

sub output_params { return $_[0]->{form}->output_params; }

=item param(param => $p)

Return the API settings for a parameter as a hashref

=cut

sub param {
    my ( $self, %params ) = @_;

    my $p = $params{param};

    return $self->{form}->param(param => $p);
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

    if( $self->read_form ) {
        return $self->{form}->guards;
    } else {
        return {};
    }
}



1;
