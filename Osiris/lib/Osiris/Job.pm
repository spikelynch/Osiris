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

Terminology for file uploads:

FILE     = the full path to the actual file
FILENAME = the filename (minus full path)  

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
        for ( qw(created started completed status to from) ) {
            $self->{$_} = $s->{$_};
        }
        $self->{appname} = $s->{app};

    } else{
        # job is being created via the web app (or a test script)
        $self->{app} = $params{app};
        $self->{appname} = $params{app}->{app};
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

Writes out this job's XML

FIXME - this has to create the parameter and file lists itself

=cut


sub write {
	my ( $self ) = @_;

    if( !-d $self->working_dir ) {
        $self->{log}->error("write called before working dir created");
    }

    if( !$self->{parameters}  ) {
        $self->{log}->error("write called before parameters added");
        return undef;
    }

    my $parameters = [];

    for my $p ( $self->{app}->params ) {
        push @$parameters, {
            name => $p,
            value => $self->{parameters}{$p}
        };
    }

    $self->{created} = $self->timestamp;
    

    $self->{xml} =<<EOXML;
<?xml version="1.0" encoding="UTF-8"?>
<job app="$self->{app}{app}">
    <metadata>
    <created>$self->{created}</created>
    </metadata>
    <parameters>
EOXML
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

=item add_parameters

Does any checking or conversion required on the parameters -
this will include parameter value checking, and making sure that
output files don't already exist etc.

This is now used for ALL parameters, as copying the input files
now happens outside this object.


=cut

sub add_parameters {
    my ( $self, %params ) = @_;

    my $phash = $params{parameters};

    $self->{parameters} = {};

    my $errors = {};

    for my $p ( $self->{app}->params  ) {
        $self->{parameters}{$p} = $phash->{$p};

        my $app_p = $self->{app}->settings(parameter => $p);

        if( $app_p->{filter} && $app_p->{field_type} eq 'output_file_field' ) {
            if( $app_p->{filter} =~ /^\*(\..*)$/ ) {
                $self->{parameters}{$p} .= $1;
            } else {
                $self->{log}->warn("Strange file filter on $p: '$app_p->{filter}'");
            }
        }
        
        if( $app_p->{field_type} eq 'input_file_field' ) {
            if( !-f $phash->{$p} ) {
                $errors->{$p} = "File $p: $phash->{$p} not found";
                $self->{log}->error($errors->{$p});
            }
        }

        if( $p eq 'TO' ) {
            $self->{to} = $self->{parameters}{$p};
        }

        if( $p eq 'FROM' ) {
            $self->{from} = $self->{parameters}{$p};
        }
    }

    if( keys %$errors ) {
        return undef;
    }
    return $self->{parameters};
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
        started => $self->{started},
        finished => $self->{finished},
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

    $self->{parameters} = {};
    $self->{metadata} = {};

    my $tw = XML::Twig->new(
        twig_handlers => {
            job => sub { $self->{appname} = $_->att('app') },
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

    my $command = [ $self->{appname} ];

    for my $name ( sort keys %{$self->{parameters}} ) {
        push @$command, join('=', $name, $self->{parameters}{$name});
    }

    $self->{command} = $command;
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

    my $f = {};

    $f->{print} = $self->_read_print_prt;
    $f->{inputs} = {};
    $f->{outputs} = {};
    $f->{other} = [];

    # Look for input files

    my $files = $self->_read_dir;

    for my $param ( $self->{app}->input_params ) {
        my $path = $self->{parameters}{$param};
        if( $path =~ /\/([^\/]+)$/ ) {
            my $ifile = $1;
            $self->{log}->debug("Matching input file ($param) $ifile");
            if( $files->{$ifile} ) {
                $self->{log}->debug("Matched $ifile");
                push @{$f->{inputs}{$param}}, $ifile;
                
                delete $files->{$ifile};
            }
        }
    }

    # Look for output files, both those which directly match the
    # params, and those with extra extensions like FILENAME.even.EXT

    for my $param ( $self->{app}->output_params ) {
        my $ofile = $self->{parameters}{$param};
        $self->{log}->debug("Matching output file ($param) $ofile");
        if( $files->{$ofile} ) {
            $self->{log}->debug("Matched $ofile");
            push @{$f->{outputs}{$param}}, $ofile;
            delete $files->{$ofile};
        } else {
            my ( $filename, $ext ) = split('\.', $ofile);
            my $pat = qr/^${filename}\..*\.${ext}$/i;
            $self->{log}->debug("Matching output file pattern ($param) $pat");
            for my $file ( keys %$files ) {
                $self->{log}->debug("-- $file");
                if( $file =~ $pat ) {
                    $self->{log}->debug("Matched $file");
                    push @{$f->{outputs}{$param}}, $file;
                    delete $files->{$file};
                }
            }
        }
    }
    
    # Anything left over gets presented as 'other'

    $self->{log}->debug(Dumper({remaining => $files}));

    push @{$f->{other}}, sort keys %$files; 


    return $f;
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

Reads the working directory for this job and returns a hashref of
filenames (relative to the working directory, with print.prt and the
job xml file filtered out)

=cut


sub _read_dir {
    my ( $self ) = @_;

    my $files = {};
    my $dir = $self->working_dir;
    my $xml = $self->xml_file;
    if( $xml =~ /\/([^\/]+)$/ ) {
        $xml = $1;
    }
    if( opendir(my $dh, $dir) ) {
        FILE: for my $file ( sort readdir($dh) ) {
            next FILE if $file eq $PRINT_PRT;
            next FILE if $file eq $xml;
            next FILE if $file =~ /^\./;
            $files->{$file} = 1;
        }
          closedir($dh);
          return $files;
    } else {
        $self->{log}->error("Couldn't open $dir for reading: $!");
        return undef;
    }
}
                

1;
