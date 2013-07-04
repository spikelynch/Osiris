package Osiris::Job;

use strict;

use Dancer ":syntax";
use File::Copy;
use XML::Twig;


=head NAME

Osiris::Job

=head DESCRIPTION

A class representing a job - an Isis app, a set of parameters, including
one or more input files, and an output filename, and a User.

This class is used by the Dancer app to create and monitor jobs, and
by the daemon to run them.

Jobs have a status, which is stored in the user's joblist file. Takes
the following values:

=over 4

=item new - value at creation

=item processing - set when the Isis process starts running

=item done - set when the Isis process completes successfully

=item error - set when the Isis process completes unsuccessfully.

=back


=head METHODS

=over 4

=item new(id, status, app, dir, files, parameters)

This is only used from Osiris::User, which maintains the user's
job list.


=cut




sub new {
	my ( $class, %params ) = @_;
	
	my $self = {};
	bless $self, $class;
	
	$self->{dir} = $params{dir};
    $self->{id} = $params{id};
    $self->{user} = $params{user};
    $self->{status} = $params{status};

    if( $params{app} ) {
        # job is being created via the web app
        $self->{app} = $params{app};
        $self->{files} = $params{files};
        $self->{parameters} = $params{parameters};
	} else {
        # job already exists, load it from XML
        # $self->_load_xml();
    }
	return $self;
}

=item status([ status => $status ])

get/set the job's status

=cut

sub status {
    my ( $self, %params ) = @_;

    if( $params{status} ) {
        $self->{status} = $params{status};
    }

    return $self->{status};
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

    $files = $self->copy_uploads || do { return undef };

    $self->{xml} = template 'job' => {
        app => $self->{app}{app},
        parameters => $parameters,
        files => $files
    }, { layout => undef };

    $self->{xmlfile} = $self->xmlfile;

    open(XML, ">$self->{xmlfile}") || do {
        error("Couldn't write to $self->{xmlfile} $!");
        return undef;
    };

    print XML $self->{xml};

    close(XML);

    return $self->{id};	
}


=item copy_uploads

Copies the upload files into the user's working directory.

If the uploads aren't Dancer upload objects, assumes that we're
testing with plain hashrefs and acts accordingly

=cut

sub copy_uploads {
    my ( $self ) = @_;

    my $files = [];

    for my $u ( $self->{app}->upload_fields ) {
        my $upload = $self->{files}{$u};
        if( ref($upload) eq 'Dancer::Request::Upload' ) {
            my $filename = $upload->filename;
            my $path = join("/", $self->{dir}, $filename);
            if( $upload->copy_to($path) ) {
                push @$files, {
                    name => $u,
                    value => $path
                };
            }  else {
                error("Couldn't copy upload to $path");
                return undef;
            }
        } else {
            # for testing
            my $filename = $upload->{filename};
            my $path = join("/", $self->{dir}, $filename);
            if( copy($upload->{file}, $path) ) {
                push @$files, { 
                    name => $u,
                    value => $path
                };
            } else {
                error("couldn't copy $upload->{file} to $path: $!");
                return undef;
            }
        }
    }
    return $files;
}


=item xmlfile

Generates and returns the full path to the job's XML file

=cut

sub xmlfile {
    my ( $self ) = @_;

    if( $self->{id} ) {
        $self->{xmlfile} = $self->{dir} . '/job_' . $self->{id} . '.xml';
        return $self->{xmlfile};
    } else {
        error("Job does not yet have an id");
        return undef;
    }
}
        


=item xml

Return the XML representation of this job

=cut

sub xml {
    my ( $self ) = @_;

    return $self->{xml};
}


1;
