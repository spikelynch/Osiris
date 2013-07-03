package Osiris::Job;

use strict;

use Dancer ":syntax";
use XML::Twig;


=head NAME

Osiris::Job

=head DESCRIPTION

A class representing a job - an Isis app, a set of parameters, including
one or more input files, and an output filename.

This class is used by the Dancer app to create and monitor jobs, and
by the daemon to run them.


=head METHODS

=over 4

=item new(app, dir, files, parameters)

Creates a new job object given the parameters and upload files from
an App's form.  This needs to also generate a unique ID - for now
all jobs are called 'job'.

=cut




sub new {
	my ( $class, %params ) = @_;
	
	my $self = {};
	bless $self, $class;
	
    $self->{id} = 'job';
	$self->{app} = $params{app};
	$self->{dir} = $params{dir};
    $self->{files} = $params{files};
    $self->{parameters} = $params{parameters};
	
	return $self;
}



=item write()

Writes out this job's XML and copies any files into the working
directory

=cut


sub write {
	my ( $self ) = @_;

    my $parameters = [];
    my $files = [];

    # Note: probably should check and fail for missing
    # parameters at this stage?

    for my $p ( $self->{app}->param_fields  ) {
        push @$parameters, {
            name => $p,
            value => $self->{parameters}{$p}
        }
    }

    for my $u ( $self->{app}->upload_fields ) {
        my $upload = $self->{files}{$u};
        my $filename = $upload->filename;
        my $path = join("/", $self->{dir}, $filename);
        if( $upload->copy_to($path) ) {
            push @$files, {
                name => $u,
                value => $path
            }
        } else {
            error("Couldn't copy upload to $path");
            return undef;
        }
    }
    $self->{xml} = template 'job' => {
        app => $self->{app}{app},
        parameters => $parameters,
        files => $files
    }, { layout => undef };

    my $xmlpath = $self->{dir} . '/' . $self->{id} . '.xml';

    open(XML, ">$xmlpath") || do {
        error("Couldn't write to $xmlpath $!");
        return undef;
    };

    print XML $self->{xml};

    close(XML);

    return $self->{id};	
}


=item xml

Return the XML representation of this job

=cut

sub xml {
    my ( $self ) = @_;

    return $self->{xml};
}


1;
