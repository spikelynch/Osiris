package Osiris::User;

use strict;

use Dancer ":syntax";
use XML::Twig;

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

	if( !-d $self->{dir} ) {
        error("User $self->{id} has no working directory ($self->{dir}).");
        return undef;
    }

    if( $self->_load_joblist ) {
        return $self;
    } else {
        return undef;
    }
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
        dir => $self->{dir},
        app => $params{app},
        id => $id,
        parameters => $params{parameters},
        files => $params{files}
    );

    if( $job ) {
        if( $job->write ) {
            $self->{joblist}{$id} = 'new';
            $self->_save_joblist();
            return $job;
        } else {
            error("Couldn't write job");
            return undef;
        }
    } else {
        error("Couldn't initialise job");
        return undef;
    }
}



=item _new_jobid

Returns a new, unique job ID

=cut

sub _new_jobid {
    my ( $self ) = @_;

    my @ids = reverse sort keys %{$self->{joblist}};
    
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
    
    $self->{jobs} = {};
   
    if( -f $joblistfile ) {
        open(JOBS, $joblistfile) || do {
            error("Couldn't read joblist file $joblistfile $!");
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
                    error("Couldn't create job $id for user $self->{id}");
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
    
    open(JOBS, ">$joblistfile") || do {
        error("Couldqn't write to joblist file $joblistfile $!");
        return undef;
    };

    for my $id ( sort keys %{$self->{jobs}} ) {
        print JOBS join(' ', $id, $self->{jobs}{$id}->status) . "\n";
    }
    return 1;
}


1;
