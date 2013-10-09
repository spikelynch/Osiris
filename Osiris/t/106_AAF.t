#!/usr/bin/perl

# Standalone test of the AAF code

use Test::More tests => 18;

use strict;
use Data::Dumper;
use FindBin;
use Cwd qw/realpath/;
use Dancer ":script";
use File::Copy;
use Log::Log4perl;

use lib "$FindBin::Bin/../lib";

use Osiris;
use Osiris::AAF;

my %ATTRIBUTES = (
    cn => 'Joe Blow',
    mail => 'Joe.Blow@inst.edu.au',
    displayname => 'Joe Reginald Blow',
    edupersontargetedid => 'anid',
    edupersonscopedaffiliation => 'probablyanemail'
    );





use_ok 'Osiris::AAF';

my $conf = config();

my $aaf = $conf->{aaftest};

ok($aaf, "Got AAF test config");

# encode a JWT

my $now = time;

my $claims = {
    iss => $aaf->{iss},
    aud => $aaf->{aud},
    nbf => $now - 100000,
    exp => $now + 100000,
    jti => "JTI$now",
    $aaf->{attributes} => \%ATTRIBUTES
};

# Create a JWT

my $oaaf = Osiris::AAF->new(config => $aaf);

ok($oaaf, "Created Osiris::AAF object");

my $jwt = $oaaf->encode(claims => $claims);
ok($jwt, "Encoded JWT");

# Decode the JWT...

my $decoded = $oaaf->decode(jwt => $jwt);

if( ok($decoded, "Decoded JWT") ) {
    cmp_ok($decoded->{iss}, 'eq', $claims->{iss}, "iss = $claims->{iss}");
    cmp_ok($decoded->{aud}, 'eq', $claims->{aud}, "aud = $claims->{aud}");
    cmp_ok($decoded->{nbf}, '<', $now, "nbf < $now");
    cmp_ok($decoded->{exp}, '>', $now, "exp > $now");

    my $atts = $oaaf->verify(claims => $decoded);

    ok($atts, "Claims verified");

    for my $attname ( keys %ATTRIBUTES ) {
        cmp_ok(
            $atts->{$attname}, 'eq', $ATTRIBUTES{$attname},
            "Attributes: $attname"
            );
    }
    
}

# Try a replay (claim with an existing JTI);

my $jwt2 = $oaaf->encode(claims => $claims);
ok($jwt2, "Encoded replay of earlier JWT");

# Decode the JWT...

my $decoded2 = $oaaf->decode(jwt => $jwt2);

if( ok($decoded2, "Decoded second JWT") ) {
    ok(!$oaaf->verify(claims => $decoded2), "Replay claim failed");
}
