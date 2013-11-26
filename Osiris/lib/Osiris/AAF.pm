package Osiris::AAF;

use strict;

use Data::Dumper;
use Log::Log4perl;
use JSON::WebToken;
use Digest::SHA qw(sha256_hex);
use Fcntl qw(:flock SEEK_END);


=head1 NAME

Osiris::AAF

=head1 SYNOPSIS

    my $oaaf = Osiris::AAF->new( config => $aafcf );
    
    my $claims = $oaaf->decode(jwt => $jwt);

    if( $claims ) {
        if( my $attributes = $oaaf->verify(claims => $claims) ) {
            if( my $user_id = $oaaf->user_id(attributes => $attributes) ) {
                 # ... Let them in ...
            } else {
                template 'error' => {
                    title => 'Error',
                    error => 'Authentication failed.'
                };
            }
        } else {
            warn("AAF JWT authentication failed");
            send_error(403, "Not allowed");
        }
    } else {
        warn("AAF JWT decryption failed");
        send_error(403, "Not allowed");
    }

=head1 DESCRIPTION

Simple Perl implementation of AAF's Rapid Connect JWT platform.

See https://rapid.aaf.edu.au/developers for details.

=head1 METHODS

=over 4

=item new(config => { ... config ... }, file => $file)

Create a new Osiris::AAF object with the given configuration parameters

=over 4

=item url: this app's AAF URL

=item iss: either the test or live AAF url

=item aud: the URL of your application

=item jtistore: a file used to store jti values to prevent replay attacks

=item secret: the secret key shared with AAF

=item attributes: the attributes key

=back

Returns the new object if successful, otherwise undef.

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

=item encode(claims => $claimshash )

Encode a claims set passed in as a hashref.  This is used to create
web tokens locally for testing this library and the Osiris endpoint
before registration with the AAF. See get /auth/fakeaff in Osiris.pm.

The claims hashref is of the form:

    {
        iss => 
        aud => 
        nbf => $not_before,
        exp => $expiry,
        jti => $jti_timestamp,
        $test_conf->{attributes} => $hash_of_test_atts.
    }

Returns a JSON web token.

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




=item decode(jwt => $jwt)

Attempt to decode a JWT assertion with the secret key.  If successful,
returns the claims as a hashref.  This is called on returning from the 
AAF, which passes the jwt to a POST method.

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

    $self->{log}->debug("Claims = " . Dumper({claims => $claims}));

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


=item user_id(attributes => $atts)

Takes a set of user attributes and returns a unique string that can
be used as a user ID (and to create working directories).

On AAF's recommendation, we're using a SHA-256 hex digest of the complete
EduPersonTargetedID string.

=cut

sub user_id {
    my ( $self, %params ) = @_;

    my $atts = $params{attributes} || do {
        $self->{log}->error("user_id needs an attributes hashref");
        return undef;
    };

    my $id = $atts->{edupersontargetedid} || do {
        $self->{log}->error("No edupersontargetedid in attributes");
        return undef;
    };

    my $user_id = sha256_hex($id);

    $self->{log}->debug("Hashed $id\n to $user_id");

    return $user_id;
}


=item store_jti(jti => $jti) 

Single method for looking up and/or storing the jti unique identifier.
These are a requirement of the AAF - we need to keep a record of timestamps
for each authentication so that we can rule out replay attacks.

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

=back

=cut


1;
        
