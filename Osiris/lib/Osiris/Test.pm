package Osiris::Test;

use parent Exporter;

our @EXPORT_OK = qw(test_fixtures);

use strict;

use File::Copy;
use File::Path qw(remove_tree);
use File::Copy::Recursive qw(dircopy);


my $TESTDIR = '/home/mike/workspace/DC18C Osiris/working';
my $FIXTURESDIR = '/home/mike/workspace/DC18C Osiris/test/fixtures';



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
