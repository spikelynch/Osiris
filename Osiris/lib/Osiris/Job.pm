package Osiris::Job;

use strict;

use File::Copy;
use XML::Twig;
use POSIX qw(strftime);

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

NOTE: in this class, 'app' refers to an Osiris::App object, and 
'appname' refers to the object's name (the actual command line program's
name.  When passing back a summary for the job, 'appname' is called 'app'.

=cut

my $TIME_FORMAT = "%d %b %Y %I:%M:%S %p";
my $PRINT_PRT = 'print.prt';


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

    if( my $s = $params{summary} ) {
        # job is being created from the job list
        for ( qw(created status to from) ) {
            $self->{$_} = $s->{$_};
        }
        $self->{appname} = $s->{app};

    } else{
        # job is being created via the web app
        $self->{app} = $params{app};
        $self->{appname} = $params{app}->{app};
        $self->{uploads} = $params{uploads};
        $self->{parameters} = $params{parameters};
	} 

	$self->{log} = Log::Log4perl->get_logger($class);


	return $self;
}

=item create_dir

Create this job's subdirectory in the user's working directory

=cut

sub create_dir {
    my ( $self ) = @_;
    
    my $basedir = $self->{user}->working_dir;

    my $path = join('/', $basedir, $self->{id});
    
    if( -d $path ) {
        $self->{log}->warn("Job working directory already exists");
        return $path;
    }

    if( mkdir($path) ) {
        return $path;
    } else {
        $self->{log}->error("Couldn't create job working directory");
        return undef;
    }
}



=item working_dir([file => $file])

Returns the directory in which this job will be run.  If a file param is
passed in, returns the complete path to a file in the directory.

=cut

sub working_dir {
    my ( $self, %params ) = @_;

    my $dir = join('/', $self->{user}->working_dir, $self->{id});
    if( $params{file} ) {
        return join('/', $dir, $params{file});
    } else {
        return $dir;
    }
}




=item write()

Writes out this job's XML and copies any files into the working
directory

=cut


sub write {
	my ( $self ) = @_;

    my $parameters = [];
    my $files = [];

    # TODO: process_params should return undef if the parameters
    # are invalid
    $parameters = $self->process_params;

    if( !$self->create_dir ) {
        return undef;
    }

    $files = $self->process_uploads || do { return undef };

    $self->{created} = $self->timestamp;
    

    $self->{xml} =<<EOXML;
<?xml version="1.0" encoding="UTF-8"?>
<job app="$self->{app}{app}">
    <metadata>
    <created>$self->{created}</created>
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


    $self->{xmlfile} = $self->xml_file;

    open(XML, ">$self->{xmlfile}") || do {
        $self->{log}->error("Couldn't write to $self->{xmlfile} $!");
        return undef;
    };

    print XML $self->{xml};

    close(XML);

    return $self->{id};	
}


=item set_status

Writes this job's status to its user's job queue.  Note that this updates
the status for this object, but refers to the job by ID when saving the
joblist - trying to cover all bases.

=cut

sub set_status {
    my ( $self, %params ) = @_;

    my $status = $params{status} || die( "set_status needs a status");

    $self->{status} = $status;

    return $self->{user}->update_joblist(
        job => $self->{id},
        status => $self->{status}
        );


}

=item process_params

Does any checking or conversion required on the parameters -
this will include parameter value checking, and making sure that
output files don't already exist etc.


=cut

sub process_params {
    my ( $self ) = @_;

    my $parameters = [];
    for my $p ( $self->{app}->params  ) {

        if( my $ff = $self->{app}->file_filter(parameter => $p) ) {
            if( $ff =~ /^\*(\..*)$/ ) {
                $self->{parameters}{$p} .= $1;
            } else {
                $self->{log}->warn("Strange file filter on $p: '$ff'");
            }
        }

        push @$parameters, {
            name => $p,
            value => $self->{parameters}{$p}
        };

        if( $p eq 'TO' ) {
            $self->{to} = $self->{parameters}{$p};
        }
    }
    return $parameters;
}


=item process_uploads

Copies the upload files into the user's working directory.

If the uploads aren't Dancer upload objects, assumes that we're
testing with plain hashrefs and acts accordingly


=cut

sub process_uploads {
    my ( $self ) = @_;

    my $files = [];

    for my $u ( $self->{app}->upload_params ) {
        my $upload = $self->{uploads}{$u};
        $self->{log}->debug(Dumper({$u => $upload}));



        if( ref($upload) eq 'Dancer::Request::Upload' ) {
            my $filename = $upload->filename;
            my $path = $self->working_dir(file => $filename);
            if( $upload->copy_to($path) ) {
                push @$files, {
                    name => $u,
                    value => $filename
                };
                $self->{files}{$u} = $filename;
                if( $u eq 'FROM' ) {
                    $self->{from} = $filename;
                }
            }  else {
                $self->{log}->error("Couldn't copy upload to $path");
                return undef;
            }
        } else {
            # for Jobs that aren't created via a web post
            # ie in tests
            my $filename = $upload->{filename};
            my $path = $self->working_dir(file => $filename);
            if( copy($upload->{file}, $filename) ) {
                push @$files, { 
                    name => $u,
                    value => $filename
                };
                if( $u eq 'FROM' ) {
                    $self->{from} = $filename;
                }
            } else {
                $self->{log}->error("couldn't copy $upload->{file} to $path: $!");
                return undef;
            }
        }
    }
    return $files;
}


=item timestamp

Returns a nicely-formatted timestamp

=cut

sub timestamp {
    my ( $self ) = @_;

    return strftime($TIME_FORMAT, localtime);
}


=item summary 

Returns a list of ( id, created, status, app, from, to ) for this job.
These are the fields stored in the jobs.txt file

=cut

sub summary {
    my ( $self ) = @_;

    my $s = {
        id => $self->{id},
        created => $self->{created},
        status => $self->{status},
        app => $self->{appname},
        from => $self->{from}, 
        to => $self->{to}
        };
    return $s;

                 
}




=item xml_file

Generates and returns the full path to the job's XML file

=cut

sub xml_file {
    my ( $self ) = @_;

    if( $self->{id} ) {
        $self->{xmlfile} = $self->working_dir(
            file => 'job_' . $self->{id} . '.xml'
            );
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
    
    my $xmlfile = $self->xml_file;
    return undef unless $xmlfile;
    $self->{files} = {};
    $self->{parameters} = {};
    $self->{metadata} = {};

    my $tw = XML::Twig->new(
        twig_handlers => {
            job => sub { $self->{appname} = $_->att('app') },
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
        if( !$self->load_xml ) {
            $self->{log}->error("Load XML failed");
            return undef;
        }
    }

    $self->{log}->debug(Dumper(
                            { files => $self->{files},
                              parameters => $self->{parameters} 
                            }));

    my $command = [ $self->{appname} ];
    for my $name ( sort keys %{$self->{files}} ) {
        push @$command, join('=', $name, $self->{files}{$name});
    }

    for my $name ( sort keys %{$self->{parameters}} ) {
        push @$command, join('=', $name, $self->{parameters}{$name});
    }

    $self->{command} = $command;
    $self->{commandstr} = join(' ', @$command);
    return $command;
}


=item files

Returns all the files associated with this job as a hashref:


{
    print => ${CONTENTS},
    input => [ { name => $field, file => $filename } , ... ],
    output => [ { name => $field, file => $filename } , ... ]
}

Note that there may be more than one file associated with a given
output field (ie FILENAME.odd.cub and FILENAME.even.cub) - this routine
tries to guess which ones match based on the job parameters.


=cut


sub files {
    my ( $self ) = @_;

    if( !$self->{app} ) {
        $self->{log}->warn("You need to set job->{app} before getting files");
        return undef;
    }

    my $files = {};

    $files->{print} = $self->_read_print_prt;
    $files->{inputs} = [];
    $files->{outputs} = [];

    # build two hashes of filenames => params, one for input files,
    # the other for output files

    my $inputs = map {
        $self->{parameters}{$_} => $_ 
    } $self->{app}->upload_params;

    my $outputs = map {
        $self->{parameters}{$_} => $_
    } $self->{app}->output_params;

    # loop through all the files in the job's directory and try to 
    # match them to an input or output filename.  _readdir automatically
    # ignores print.prt and job_n.xml.

    FILE: for my $file ( $self->_read_dir ) {
        if( my $param = $inputs->{$file} ) {
            push @{$files->{inputs}}, {
                name => $param, file => $file
            };
            next FILE;
        } 
        if( my $param = $outputs->{$file} ) {
            push @{$files->{outputs}}, {
                name => $param, file => $file
            };
            next FILE;
        }
        # a file which hasn't matched either an explicit
        # input or output.  Try to
    }
    return $files;
}



sub _read_print_prt {
    my ( $self ) = @_;

    my $printprt = $self->working_dir(file => $PRINT_PRT);

    open(my $fh, $printprt) || do {
        $self->{log}->error("Couldn't open $printprt: $!");
        return undef;
    };

    local $/;
    my $content = <$fh>;
    close $fh;

    return $content;
}

=item _read_dir()

Reads the working directory for this job and returns a list of
files (with print.prt and the job.xml file filtered out)

=cut


sub _read_dir {
    my ( $self ) = @_;

    my @files = ();
    my $dir = $self->working_dir;
    my $xml = $self->xml_file;
    if( opendir(my $dh, $dir) ) {
        FILE: for my $file ( sort readdir($dh) ) {
            next FILE if $file eq $PRINT_PRT;
            next FILE if $file eq $xml;
            next FILE if $file =~ /^\./;
            next FILE unless -f $file;
            push @files;
        }
          closedir($dh);
          return @files;
    } else {
        $self->{log}->error("Couldn't open $dir for reading: $!");
        return undef;
    }
}
                

1;
