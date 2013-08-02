package Osiris::User;

use strict;

use Data::Dumper;
use XML::Twig;
use Log::Log4perl;


use Osiris::Job;

=head NAME

Osiris::User

=head DESCRIPTION

A class representing a user.  It maintains the user's working
directory and list of jobs and their status.

=cut

our $JOBLISTFILE = 'joblist.xml';


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
    $self->{isisdir} = $params{isisdir};

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


=item create_job(app => $app)

Method used by the Dancer app to create a new job for this user.
Used to also take the uploads and parameters, but these are now added 
separately by calling add_parameters and add_input_files on the
Job.

=cut

sub create_job {
    my ( $self, %params ) = @_;

    my $id = $self->_new_jobid;

    my $job = Osiris::Job->new(
        user => $self,
        app => $params{app},
        id => $id,
    );
    
    return undef unless $job;

    if( $job->create_dir ) {
        return $job;
    } else {
        return undef;
    }
}




sub write_job {
    my ( $self, %params ) = @_;

    my $job = $params{job};
    if( $job->write ) {
        $self->{jobs}{$job->{id}} = $job;
        $job->{status} = 'new';
        $self->_save_joblist;
        return $job;
    } else {
        $self->{log}->error("Couldn't write job");
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

    $self->{log}->warn("_load_joblist: " . join(' ', caller));
 
    $self->{jobs} = {};
   
    if( -f $joblistfile ) {
        my $tw = XML::Twig->new(
            twig_handlers => { job => sub { $self->_load_job($_) } }
            );
        eval { $tw->parsefile($joblistfile) };
        if( $@ ) {
            $self->{log}->error("Joblist parse failed: $@");
            return undef;
        }
    }
    return $self->{jobs};
}




=item _load_job

XML::Twig handler to read a single job element

=cut



sub _load_job {
    my ( $self, $elt ) = @_;
    my $s = $elt->atts;
    if( $s->{id} =~ /^\d$/ ) {
        $self->{jobs}{$s->{id}} = Osiris::Job->new(
            id => $s->{id}, 
            user => $self,
            summary => $s
            ) || do {
                $self->{log}->error("Couldn't create job")
        };
    }
}





=item _save_joblist

Saves the storable job list, if it exists

=cut

sub _save_joblist {
    my ( $self ) = @_;

    my $joblistfile = $self->_joblistfile;
    
    open(JOBS, ">$joblistfile") || do {
        $self->{log}->error("Couldn't write to joblist file $joblistfile $!");
        return undef;
    };

    print JOBS <<EOXML;
<?xml version="1.0" encoding="UTF-8"?>
<joblist user="$self->{id}">
EOXML

    for my $id ( sort keys %{$self->{jobs}} ) {
        print JOBS $self->_job_elt($self->{jobs}{$id}) . "\n";
    }

    print JOBS <<EOXML;
</joblist>
EOXML
    close JOBS;
    return 1;
}

=item _save_job

Returns a job as an XML element for the joblist

=cut

sub _job_elt {
    my ( $self, $job ) = @_;

    my $s = $job->summary;

    my $atts = join(' ', map { "$_=\"$s->{$_}\"" } sort keys %$s);
    
    return "<job $atts />";
}


    


=item update_joblist( job => $job, status => $status )

Public version of _save_joblist.  This looks the job up by id, rather
than just updating the job object, because the job list may have been
reloaded on the user betweentimes.

The job can be passed as an ID or an Osiris::Job.  

This hasn't been changed drastically from when the joblist was a textfile
with just id and status - so it can't be used to modify any of the other
joblist fields.  But they shouldn't change anyway.


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
        
