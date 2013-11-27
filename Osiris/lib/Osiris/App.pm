package Osiris::App;

use strict;

use Log::Log4perl;
use Data::Dumper;

use Osiris::Form;

=head1 NAME

Osiris::App

=head1 SYNOPSIS

   	my $app = Osiris::App->new(
		dir => $conf->{isisdir},
		app => $name,
		brief => $toc->{$name}
	);

    my $form = $app->read_form;

    my $params = $app->params;
    
    my $in_params = $app->input_params;

    my $out_params = $app->output_params;



=head1 DESCRIPTION

A class representing an Isis app.  Uses Osiris::Form to parse the XML for
the web form API.


=head1 METHODS

=over 4

=item new(%params)

=over 4

=item app: the application's command name

=item dir: the Isis base directory

=item brief: the brief description from the TOC file

=back

Creates a new Osiris::App object, populating it with the command name (app)
and the brief description.

This is done at startup by the Dancer app in the method Osiris::load_toc,
which parses the Isis table of contents XML file.

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
object. Returns undef if the parse fails.

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

Parses the form, and returns a data structure which can be used to fill 
out the form.tt template. This is not the Osiris::Form object, but the
return value of Osiris::Form->groups - see Osiris::Form for more details.

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

Returns all this form's guards as a hashref-by-parameter name which can
be passed into the form templates and javascript guards.

See Osiris::Form::guards for details.

=cut

sub guards {
    my ( $self, %params ) = @_;

    if( $self->read_form ) {
        return $self->{form}->guards;
    } else {
        return {};
    }
}


=back

=cut


1;
