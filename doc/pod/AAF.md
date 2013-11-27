# NAME

Osiris::AAF

# SYNOPSIS

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

# DESCRIPTION

Simple Perl implementation of AAF's Rapid Connect JWT platform.

See https://rapid.aaf.edu.au/developers for details.

# METHODS

- new(config => { ... config ... }, file => $file)

    Create a new Osiris::AAF object with the given configuration parameters

    - url: this app's AAF URL
    - iss: either the test or live AAF url
    - aud: the URL of your application
    - jtistore: a file used to store jti values to prevent replay attacks
    - secret: the secret key shared with AAF
    - attributes: the attributes key

    Returns the new object if successful, otherwise undef.

- encode(claims => $claimshash )

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

- decode(jwt => $jwt)

    Attempt to decode a JWT assertion with the secret key.  If successful,
    returns the claims as a hashref.  This is called on returning from the 
    AAF, which passes the jwt to a POST method.

- verify(claims => $claims)

    Verify the claims hashref against the config values, the current time
    and the jti store.  Writes errors into the logs for any mismatches.

    The AAF attributes (cn, mail, displayname etc) are returned as a claim
    called 'https://aaf.edu.au/attributes' - the URL to use for looking this
    up is configured as aaf.attributes.

- user\_id(attributes => $atts)

    Takes a set of user attributes and returns a unique string that can
    be used as a user ID (and to create working directories).

    On AAF's recommendation, we're using a SHA-256 hex digest of the complete
    EduPersonTargetedID string.

- store\_jti(jti => $jti) 

    Single method for looking up and/or storing the jti unique identifier.
    These are a requirement of the AAF - we need to keep a record of timestamps
    for each authentication so that we can rule out replay attacks.

    Tries to get a lock on the jti file, and when it does, looks up the jti.

    If the jti is found, release the file and return undef (because this
    is evidence of a replay attack).

    If it's not found, add it to the store and write and release the file,
    return true.
