package Osiris::User;

use strict;

use XML::Twig;
use Log::Log4perl;


use Osiris::App;
use Osiris::Job;

=head NAME

Osiris::User

=head DESCRIPTION

A class representing a user.  It maintains the user's working
directory and list of jobs and their status.

=cut

our $JOBLISTFILE = 'jobs.txt';


=head METHODS

=over 4

=item new(id => $id, basedir => $home)

"home" is the base working directory: each user has a subdirectory
under this directory

=cut


sub new {
	my ( $class, %params ) = @_;
	
	my $self = {};
	bless $self, $class;
	
	$self->{id} = $params{id};
   	$self->{basedir} = $params{basedir};

    $self->{dir} = join('/', $self->{basedir}, $self->{id});

    $self->{log} = Log::Log4perl->get_logger($class);


	if( !-d $self->{dir} ) {
        $self->{log}->error("User $self->{id} has no working directory ($self->{dir}).");
        return undef;
    }

    if( $self->load_joblist ) {
        return $self;
    } else {
        return undef;
    }
}

=item jobs

Returns the job list as a hashref of Osiris::Job objects keyed by ID.
The jobs will only know their status and id - to parse their XML file,
call $job->load.

To force a reload, pass in reload => 1

=cut

sub jobs {
    my ( $self,  %params ) = @_;

    if( $params{reload} ) {
        $self->load_joblist;
    }
    
    return $self->{jobs};
}


=item create_job(app => $app, parameters => $p, files => $f)

Method used by the Dancer app to create a new job for this user.
Parameters and files are the data entered by the used in the app's
web form.  Returns an Osiris::Job if successful, otherwise undef.

=cut

sub create_job {
    my ( $self, %params ) = @_;

    my $id = $self->_new_jobid;

    my $job = Osiris::Job->new(
        user => $self,
        app => $params{app},
        id => $id,
        parameters => $params{parameters},
        uploads => $params{uploads}
    );

    if( $job ) {
        if( $job->write ) {
            $self->{jobs}{$id} = $job;
            $job->{status} = 'new';
            $self->save_joblist;
            return $job;
        } else {
            $self->{log}->error("Couldn't write job");
            return undef;
        }
    } else {
        $self->{log}->error("Couldn't initialise job");
        return undef;
    }
}


        


=item _new_jobid

Returns a new, unique job ID

=cut

sub _new_jobid {
    my ( $self ) = @_;

    my @ids = reverse sort keys %{$self->{jobs}};
    
    if( @ids ) {
        return $ids[0] + 1;
    } else {
        return 1;
    }
}



=item _joblistfile

Full path to the joblist file.

=cut

sub _joblistfile {
    my ( $self ) = @_;

    return join('/', $self->{dir}, $JOBLISTFILE);
}


=item load_joblist

Load the storable job list, if it exists

=cut

sub load_joblist {
    my ( $self ) = @_;

    my $joblistfile = $self->_joblistfile;
    
    $self->{jobs} = {};
   
    if( -f $joblistfile ) {
        open(JOBS, $joblistfile) || do {
            $self->{log}->error("Couldn't read joblist file $joblistfile $!");
            return undef;
        };

 
        while( <JOBS> ) {
            chomp;
            if( /^(\d+)\s+([a-zA-Z]+)/ ) {
                my ( $id, $status ) = ( $1, $2 );
                my $job = Osiris::Job->new(
                    user => $self,
                    id => $id,
                    status => $status
                    );
                if( $job ) {
                    $self->{jobs}{$id} = $job;
                } else {
                    $self->{log}->error("Couldn't create job $id for user $self->{id}");
                }
            }
        }
    }
    return $self->{jobs};
}


=item save_joblist

Saves the storable job list, if it exists

=cut

sub save_joblist {
    my ( $self ) = @_;

    my $joblistfile = $self->_joblistfile;
    
    $self->{log}->debug("Saving joblist for $self->{id}");
    open(JOBS, ">$joblistfile") || do {
        $self->{log}->error("Couldn't write to joblist file $joblistfile $!");
        return undef;
    };

    for my $id ( sort keys %{$self->{jobs}} ) {
        $self->{log}->debug("Job $self->{jobs}{$id} $id status = $self->{jobs}{$id}{status}");
        my $line = join(' ', $id, $self->{jobs}{$id}{status}) . "\n";
        print JOBS $line;
    }
    $self->{log}->debug("Done.");
    close JOBS;
    return 1;
}


1;
