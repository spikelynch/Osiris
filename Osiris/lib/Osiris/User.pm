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

    if( $self->_load_joblist ) {
        return $self;
    } else {
        return undef;
    }
}


=item working_dir 

Return this user's working dir (basedir/user_id)

=cut

sub working_dir {
    my ( $self ) = @_;
    
    return $self->{dir};
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
        $self->_load_joblist;
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
            $self->_save_joblist;
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


=item _load_joblist

Load the storable job list, if it exists

=cut

sub _load_joblist {
    my ( $self ) = @_;

    my $joblistfile = $self->_joblistfile;
 
    $self->{log}->debug("Reading joblist for user $self->{id}");
   
    $self->{jobs} = {};
   
    if( -f $joblistfile ) {
        open(JOBS, $joblistfile) || do {
            $self->{log}->error("Couldn't read joblist file $joblistfile $!");
            return undef;
        };

 
        while( <JOBS> ) {
            chomp;
            my ( $id, $date, $status, $app, $from, $to ) = split(',');
            if( $id =~ /^(\d+)$/ ) {
                my ( $id, $status ) = ( $1, $2 );
                my $job = Osiris::Job->new(
                    user => $self,
                    id => $id,
                    summary => {
                        date => $date,
                        status => $status,
                        app => $app,
                        from => $from,
                        to => $to
                    }
                    );
                if( $job ) {
                    $self->{jobs}{$id} = $job;
                    $self->{log}->debug("Job $id = $job");
                } else {
                    $self->{log}->error("Couldn't create job $id for user $self->{id}");
                }
            }
        }
    }
    return $self->{jobs};
}





=item _save_joblist

Saves the storable job list, if it exists

=cut

sub _save_joblist {
    my ( $self ) = @_;

    my $joblistfile = $self->_joblistfile;
    
    $self->{log}->debug("Saving joblist for $self->{id}");
    open(JOBS, ">$joblistfile") || do {
        $self->{log}->error("Couldn't write to joblist file $joblistfile $!");
        return undef;
    };

    for my $id ( sort keys %{$self->{jobs}} ) {
        my $line = join(',', $self->{jobs}{$id}->summary) . "\n";
        print JOBS $line;
    }
    $self->{log}->debug("Done.");
    close JOBS;
    return 1;
}


=item update_joblist( job => $job, status => $status )

Public version of _save_joblist.  This looks the job up by id, rather
than just updating the job object, because the job list may have been
reloaded on the user betweentimes.

The job can be passed as an ID or an Osiris::Job.  

=cut




sub update_joblist {
    my ( $self, %params ) = @_;

    my $job = $params{job};
    my $status = $params{status};

    if( !$job ) {
        $self->{log}->error("update_joblist needs a job");
        return undef;
    }

    if( !$status ) {
        $self->{log}->error("update_joblist needs a status");
        return undef;
    }
    my $id;

    if( ref($job) ) {
        $job->{status} = $status;
        $id = $job->{id} || do {
            $self->{log}->error("No job id!");
            return undef;
        };
    } else {
        $id = $job;
    }

    if( my $j = $self->{jobs}{$id} ) {
        $j->{status} = $status;
        return $self->_save_joblist;
    }
    $self->{log}->error("Job $id not found");
    return undef;
}




1;
