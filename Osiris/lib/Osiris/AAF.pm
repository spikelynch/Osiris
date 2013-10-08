package Osiris::AAF;

use strict;

use Data::Dumper;
use Log::Log4perl;
use JSON::WebToken;
use Fcntl qw(:flock SEEK_END);


Use Osiris::Job;

=head NAME

Osiris::AAF

=head DESCRIPTION

Simple Perl implementation of AAF's Rapid Connect JWT platform.

See https://rapid.aaf.edu.au/developers for details.

=head METHODS

=over 4

=item new(config => { ... config ... }, file => $file)

Create a new Osiris::AAF object with the given config.

$file is the full path to the file used to store JITs.

=cut

sub new {
	my ( $class, %params ) = @_;
	
	my $self = {};
	bless $self, $class;

	$self->{log} = Log::Log4perl->get_logger($class);

    if( !$params{config} ) {
        $self->{log}->error("No config for $class");
        die;
    }

    for my $val ( keys %{$params{config}} ) {
        $self->{log}->debug("Config $val = $params{$val}");
        $self->{$val} = $params{config}->{$val};
    }

    if( !$params{jitstore} ) {
        $self->{log}->error("No JIT jitstore for $class");
        die;
    }

    $self->{jitstore} = $params{jitstore};

    if( ! -f $self->{jitstore} ) {
        $self->{log}->error("jitstore $self->{jistore} not found");
        return undef;
    }


	return $self;
}

=item encode(claim => { ... claim ... }, secret => $key)

Encode a claim passed in as a hashref.  This is used to create web tokens
locally to test this library and the Osiris endpoint before registration
with the AAF.

=cut


sub encode {
    my ( $self, %params ) = @_;
    
    my $claim = $params{claim};
    my $secret = $params{secret};

    if( !$claim || !$secret ) {
        $self->{log}->error("encode method needs 'claim' and 'secret' parameters");
        return undef;
    }

    my $jwt = encode_jwt($claim, $secret);

    return $jwt;
}




=item decode(jwt => $assertion, secret => $key)

Attempt to decode a JWT assertion with the secret key.  If successful,
returns the claims as a hashref

=cut


sub decode {
    my ( $self, %params ) = @_;
    
    my $jwt = $params{jwt);
    my $secret = $params{secret};

    if( !$jwt || !$secret ) {
        $self->{log}->error("encode method needs 'jwt' and 'secret' parameters");
        return undef;
    }

    my $claims = decode_jwt($jwt, $secret);

    return $claims;
}

=item verify(claims => $claims)

Verify the claims hashref against the config values, the current time
and the jit store.  Writes errors into the logs for any mismatches.


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
        $self->{log}->error("Duplicate jti = $claims->{jti}");
        $success = 0;
    } 

    if( !$success ) {
        $self->{log}->error("JWT authentication failed.");
    }

    return $success;
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

    open(my $fh, "<$self->{jtistore}") || do {
        $self->{log}->error("Couldn't open $self->{jtistore}: $!");
        return undef;
    };

    flock($fh, LOCK_SH) || do { 
        $self->{log}->error("Can't lock $self->{jtistore}: $!");
        return undef;
    };

    my %jtis;

    while( my $l = <$fh> ) { 
        chomp $l;
        my ( $jti, $timestamp ) = split(/ /, $l);
        if( $jti eq $new_jti ) {
            $self->{log}->error("Warning: duplicate jti: $jti $timestamp");
            close($fh);
            return undef;
        }
        $jtis{$jti} = $timestamp;
    }

    close($fh);
    
    $jtis{$new_jti} = time;

    open(my $fh, ">$self->{jtistore}") || do {
        $self->{log}->error("Couldn't open $self->{jtistore}: $!");
        return undef;
    };

    flock($fh, LOCK_EX) || do { 
        $self->{log}->error("Can't lock_ex $self->{jtistore}: $!");
        return undef;
    };

    for my $k ( sort { $a <=> $b } keys %jtis ) {
        print $fh "$k $jtis{$k}\n";
    }

    close($fh);

    return 1;
}






    



1;
        
