package Osiris::Test;

use parent Exporter;

our @EXPORT_OK = qw(test_fixtures);

use strict;

use File::Copy;
use File::Path qw(remove_tree);
use File::Copy::Recursive qw(dircopy);

=head1 NAME

Osiris::Test

=head1 SYNOPSIS


    use Osiris::Test qw(test_fixtures);

    ok( test_fixtures(), "Copied fixtures");

=head1 DESCRIPTION

Copies the test fixtures (a set of working directories) to a test
working dir.

=cut


my $TESTDIR = '/home/mike/workspace/DC18C Osiris/working';
my $FIXTURESDIR = '/home/mike/workspace/DC18C Osiris/test/fixtures';


=head1 METHODS

=over 4

=item text_fixtures()

Copies the test fixtures

=back

=cut


sub test_fixtures {
    if( ! -d $FIXTURESDIR ) {
        die("'$FIXTURESDIR' is not a directory");
    }
	
	
    if( -d $TESTDIR ) {
        print("Cleaning out $TESTDIR\n");
        remove_tree($TESTDIR, { keep_root => 1 });
    } else {
        print("Creating $TESTDIR\n");
        mkdir($TESTDIR) || die("Couldn't mkdir $TESTDIR: $!");
    }
    
    
    my $n = dircopy($FIXTURESDIR, $TESTDIR);
    
    print "Copied $n files\n";
    if( !$n ) {
        die("Copy failed: $!");
    }

    return 1;
    
}

1;
