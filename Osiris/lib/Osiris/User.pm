package Osiris::User;

use strict;

use Data::Dumper;
use XML::Twig;
use Log::Log4perl;


use Osiris::Job;

=head1 NAME

Osiris::User


=head1 SYNOPSIS

    $user = Osiris::User->new(
        id => session('user'),
        name => $atts->{cn},
        atts => $atts,
        isisdir => $conf->{isisdir},
        basedir => $conf->{workingdir}
    );
    
    if( !$user ) {
        error("Couldn't create Osiris::User object");
        session->destroy;
        redirect '/auth/login';
    }
    
    my $jobshash = $user->jobs(reload => 1);


=head1 DESCRIPTION

A class representing a user.  It maintains the user's working
directory and list of jobs and their status, and contains their login
attributes.

It's also used to create new jobs.

=cut

our $JOBLISTFILE = 'joblist.xml';


=head1 METHODS

=over 4

=item new(%params)

Create a new user object. Parameters as follows:

=over 4

=item id - the user's identifier (a hashed AAF digest, in this case)

=item basedir - the main working dir, containing all of the user dirs

=item isisdir - the root directory of the Isis install

=item mail - the user's email

=item name - the user's screen name

=back

Returns undef if something goes wrong reading or creating the user's
joblist.

=cut


sub new {
	my ( $class, %params ) = @_;
	
	my $self = {};
	bless $self, $class;
	
	$self->{id} = $params{id};
   	$self->{basedir} = $params{basedir};
    $self->{isisdir} = $params{isisdir};
    $self->{mail} = $params{mail};
    $self->{name} = $params{name};

    $self->{dir} = join('/', $self->{basedir}, $self->{id});
    $self->{log} = Log::Log4perl->get_logger($class);

    if( $self->_load_joblist ) {
        return $self;
    } else {
        return undef;
    }
}


=item working_dir()

Return this user's working dir (basedir/user_id)

=cut

sub working_dir {
    my ( $self ) = @_;
    
    return $self->{dir};
}

=item _ensure_working_dir()

Checks if the working directory exists, and tries to create it if it 
doesn't.  If the directory exists or was created successfully, returns
1, otherwise undef.

=cut

sub _ensure_working_dir() {
    my ( $self ) = @_;

    if( -d $self->{dir} ) {
        return 1;
    }

    if( mkdir($self->{dir}) ) {
        $self->{log}->info("Created working dir $self->{dir}");
        return 1;
    } else {
        $self->{log}->error("Error creating working dir $self->{dir} $!");
    }
    return undef;
}
    

=item jobs([ reload => 1 ])

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

Returns the Osiris::Job object if successful, undef if not.

=cut

sub create_job {
    my ( $self, %params ) = @_;

    if( !$self->_ensure_working_dir ) {
        return undef;
    }

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


=item write_job(job => $job)

How the joblist and job files are updated.  Takes an Osiris::Job, calls its
write method, and then updates the job list and tries to write that.  Returns
the job if successful, undef if not.

=cut


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


=item _new_jobid()

Returns a new, unique job ID

=cut

sub _new_jobid {
    my ( $self ) = @_;

    my @ids = sort { $b <=> $a } keys %{$self->{jobs}};
    
    if( @ids ) {
        return $ids[0] + 1;
    } else {
        return 1;
    }
}



=item _joblistfile()

Full path to the joblist file.

=cut

sub _joblistfile {
    my ( $self ) = @_;

    return join('/', $self->{dir}, $JOBLISTFILE);
}


=item _load_joblist()

Load the user's job list, if it exists.  Otherwise initialises the 
{jobs} member variable to an empty hashref.

=cut

sub _load_joblist {
    my ( $self ) = @_;

    my $joblistfile = $self->_joblistfile;

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
    my @ids = keys %{$self->{jobs}};

    return $self->{jobs};
}




=item _load_job($elt)

XML::Twig handler to read a single job element

=cut



sub _load_job {
    my ( $self, $elt ) = @_;
    my $s = $elt->atts;

    if( $s->{id} =~ /^\d+$/ ) {
        $self->{jobs}{$s->{id}} = Osiris::Job->new(
            id => $s->{id}, 
            user => $self,
            summary => $s
            ) || do {
                $self->{log}->error("Couldn't create job for $s->{id}")
        };
    }
}





=item _save_joblist()

Saves the job list.

=cut

sub _save_joblist {
    my ( $self ) = @_;

    if( !$self->_ensure_working_dir ) {
        return undef;
    }

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

=item _save_job()

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


=back

=cut


1;
        
