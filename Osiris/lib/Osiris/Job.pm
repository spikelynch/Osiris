package Osiris::Job;

use strict;

use File::Copy;
use XML::Twig;

use Data::Dumper;
use Log::Log4perl;

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

=item new(id, dir)

This is only used from Osiris::User, which maintains the user's
job list.


=cut




sub new {
	my ( $class, %params ) = @_;
	
	my $self = {};
	bless $self, $class;
	
    $self->{id} = $params{id};
    $self->{user} = $params{user};
    $self->{status} = $params{status};

    $self->{dir} = $self->{user}{dir}; # FIXME JOBDIR

    if( $params{app} ) {
        # job is being created via the web app
        $self->{app} = $params{app};
        $self->{uploads} = $params{uploads};
        $self->{parameters} = $params{parameters};
	}  

	$self->{log} = Log::Log4perl->get_logger($class);


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
    $self->{log}->debug("Parameters = " . Dumper({p => $parameters}));

    $files = $self->copy_uploads || do { return undef };

    $self->{xml} =<<EOXML;
<?xml version="1.0" encoding="UTF-8"?>
<job app="$self->{app}">
    <metadata>
    </metadata>
    <files>
EOXML
    for my $file ( @$files ) {
        $self->{xml} .= "<file name=\"$file->{name}\">$file->{value}</file>\n";
    }
    $self->{xml} .= "</files>\n><parameters>\n";
    for my $parameter ( @$parameters ) {
        $self->{xml} .= "<parameter name=\"$parameter->{name}\">$parameter->{value}</parameter>\n";
    }
    $self->{xml} .= <<EOXML;
    </parameters>
</job>
EOXML


    $self->{xmlfile} = $self->xmlfile;

    open(XML, ">$self->{xmlfile}") || do {
        $self->{log}->error("Couldn't write to $self->{xmlfile} $!");
        return undef;
    };

    print XML $self->{xml};

    close(XML);

    return $self->{id};	
}


=item set_status

Writes this job's status to its user's job queue

=cut

sub set_status {
    my ( $self, %params ) = @_;

    my $status = $params{status} || die( "set_status needs a status");

    return $self->{user}->set_job_status(id => $self->{id}, status => $status);
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
        my $upload = $self->{uploads}{$u};
        if( ref($upload) eq 'Dancer::Request::Upload' ) {
            my $filename = $upload->filename;
            my $path = join("/", $self->{dir}, $filename);
            if( $upload->copy_to($path) ) {
                push @$files, {
                    name => $u,
                    value => $path
                };
                $self->{files}{$u} = $path;
            }  else {
                $self->{log}->error("Couldn't copy upload to $path");
                return undef;
            }
        } else {
            # for Jobs that aren't created via a web post
            # ie in tests
            my $filename = $upload->{filename};
            my $path = join("/", $self->{dir}, $filename);
            if( copy($upload->{file}, $path) ) {
                push @$files, { 
                    name => $u,
                    value => $path
                };
            } else {
                $self->{log}->error("couldn't copy $upload->{file} to $path: $!");
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
        $self->{log}->error("Job does not yet have an id");
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


=item read_xml

Reads a job from the XML file in the user's working directory

=cut

sub load_xml {
    my ( $self ) = @_;
    
    my $xmlfile = $self->xmlfile;
    return undef unless $xmlfile;
    $self->{files} = {};
    $self->{parameters} = {};
    $self->{metadata} = {};

    my $tw = XML::Twig->new(
        twig_handlers => {
            job => sub { $self->{app} = $_->att('app') },
            file => sub { 
                $self->{files}{$_->att('name')} = $_->text;
            },
            parameter => sub {
                $self->{parameters}{$_->att('name')} = $_->text
            },
            metadata => sub {
                for my $child ( $_->children ) {
                     $self->{metadata}{$child->tag} = $child->text;
                }
            }
        }
        );

    eval { $tw->parsefile($xmlfile) };

    if( $@ ) {
        $self->{log}->error("Parse $xmlfile failed $@");
        return undef;
    }

    return 1;
}




=item command

Returns an arrayref of command-line arguments that Ptah (the processing
daemon) can pass to exec.

=cut

sub command {
    my ( $self ) = @_;

    if( !$self->{app} ) {
        $self->{log}->error(
            "You have to load a job's XML before running command"
            );
        return undef;
    }

    my $command = [ $self->{app} ];
    for my $name ( sort keys %{$self->{files}} ) {
        push @$command, join('=', $name, $self->{files}{$name});
    }

    for my $name ( sort keys %{$self->{parameters}} ) {
        push @$command, join('=', $name, $self->{parameters}{$name});
    }

    return $command;
}


1;
