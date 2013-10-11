#!/bin/bash

export OSIRIS=/path/to/Osiris
export OSIRIS_LIB=$OSIRIS/lib
export OSIRIS_PTAHLOG=$OSIRIS/environments/ptahlog.conf

# Note that the Osiris web service needs to be able to write to
# OSIRIS_WORKING

export OSIRIS_WORKING=/path/to/working

export ISISROOT=/path/to/isis/isis
export ISIS3DATA=/path/to/isis/data

export PATH=$PATH:$ISISROOT/bin
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$ISISROOT/lib

$OSIRIS/Osiris/bin/ptah.pl

