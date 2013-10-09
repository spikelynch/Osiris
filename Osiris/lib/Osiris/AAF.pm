package Osiris::AAF;

use strict;

use Data::Dumper;
use Log::Log4perl;
use JSON::WebToken;
use Fcntl qw(:flock SEEK_END);


=head NAME

Osiris::AAF

=head DESCRIPTION

Simple Perl implementation of AAF's Rapid Connect JWT platform.

See https://rapid.aaf.edu.au/developers for details.

=head METHODS

=over 4

=item new(config => { ... config ... }, file => $file)

Create a new Osiris::AAF object with the given config.


=cut

my @CONFIG_VARS = qw(iss aud jtistore secret attributes);


sub new {
	my ( $class, %params ) = @_;
	
	my $self = {};
	bless $self, $class;

	$self->{log} = Log::Log4perl->get_logger($class);

    if( !$params{config} ) {
        $self->{log}->error("No config for $class");
        die;
    }

    my $missing = 0;

    for my $val ( @CONFIG_VARS ) {
        $self->{$val} = $params{config}->{$val} || do {
            $self->{log}->error("Missing config parameter $val");
            $missing = 1;
        }
    }

    if( $missing ) {
        $self->{log}->error("Incomplete config");
        return undef;
    }

	return $self;
}

=item encode(claims => { ... claim1 => value ... })

Encode a claims set passed in as a hashref.  This is used to create
web tokens locally to test this library and the Osiris endpoint before
registration with the AAF.

=cut


sub encode {
    my ( $self, %params ) = @_;
    
    my $claims = $params{claims};

    if( !$claims ) {
        $self->{log}->error(
            "encode method needs 'claims' parameter"
            );
        return undef;
    }

    my $jwt = encode_jwt($claims, $self->{secret});

    return $jwt;
}




=item decode(jwt => $assertion)

Attempt to decode a JWT assertion with the secret key.  If successful,
returns the claims as a hashref

=cut


sub decode {
    my ( $self, %params ) = @_;
    
    my $jwt = $params{jwt};

    if( !$jwt ) {
        $self->{log}->error("encode method needs 'jwt'");
        return undef;
    }

    return decode_jwt($jwt, $self->{secret});
}

=item verify(claims => $claims)

Verify the claims hashref against the config values, the current time
and the jti store.  Writes errors into the logs for any mismatches.

The AAF attributes (cn, mail, displayname etc) are returned as a claim
called 'https://aaf.edu.au/attributes' - the URL to use for looking this
up is configured as aaf.attributes.

=cut

sub verify {
    my ( $self, %params ) = @_;

    my $claims = $params{claims};
    
    if( !$claims ) {
        $self->{log}->error("verify needs a claims hashref");
        return undef;
    }

    my $now = time;
    my $success = 1;

    if( $claims->{iss} ne $self->{iss} ) {
        $self->{log}->error("iss mismatch: $claims->{iss}");
        $success = 0;
    }

    if( $claims->{aud} ne $self->{aud} ) {
        $self->{log}->error("aud mismatch: $claims->{aud}");
        $success = 0;
    }

    if( $now <= $claims->{nbf} ) {
        $self->{log}->error("Current time $now is earlier than nbf $claims->{nbf}");
        $success = 0;
    }

    if( $now >= $claims->{exp} ) {
        $self->{log}->error("Current time $now is later than exp $claims->{exp}");
        $success = 0;
    }

    if( !$self->store_jti(jti => $claims->{jti}) ) {
        $self->{log}->error("JTI storage failed");
        $success = 0;
    } 

    if( !$success ) {
        $self->{log}->error("JWT authentication failed.");
    }

    if( $success ) {
        return $claims->{$self->{attributes}};
    } else {
        return undef;
    }

}



=item store_jti(jti => $jti) 

Single method for looking up and/or storing the jti unique identifier.

Tries to get a lock on the jti file, and when it does, looks up the jti.

If the jti is found, release the file and return undef (because this
is evidence of a replay attack).

If it's not found, add it to the store and write and release the file,
return true.

=cut

sub store_jti {
    my ( $self, %params ) = @_;

    my $new_jti = $params{jti};

    my %jtis;

    if( ! -f $self->{jtistore} ) {
        $self->{log}->warn("JTI store $self->{jtistore} not found: creating");
        %jtis = ();
    } else {

        open(my $fh, "<$self->{jtistore}") || do {
            $self->{log}->error("Couldn't open $self->{jtistore}: $!");
            return undef;
        };
        
        flock($fh, LOCK_SH) || do { 
            $self->{log}->error("Can't lock $self->{jtistore}: $!");
            return undef;
        };
        
        
        while( my $l = <$fh> ) { 
            chomp $l;
            my ( $jti, $timestamp ) = split(/ /, $l);
            if( $jti eq $new_jti ) {
                $self->{log}->error("Duplicate jti: $jti $timestamp");
                close($fh);
                return undef;
            }
            $jtis{$jti} = $timestamp;
        }
        
        close($fh);
    }
    
    $jtis{$new_jti} = time;

    open(my $fh, ">$self->{jtistore}") || do {
        $self->{log}->error("Couldn't open $self->{jtistore}: $!");
        return undef;
    };

    flock($fh, LOCK_EX) || do { 
        $self->{log}->error("Can't lock_ex $self->{jtistore}: $!");
        return undef;
    };

    for my $k ( sort { $a cmp $b } keys %jtis ) {
        print $fh "$k $jtis{$k}\n";
    }

    close($fh);

    return 1;
}






    



1;
        
