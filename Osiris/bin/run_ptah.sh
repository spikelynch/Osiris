#!/bin/bash

export OSIRIS=where/you/installed/it
export OSIRIS_LIB=$OSIRIS/Osiris/lib
export OSIRIS_PTAHLOG=$OSIRIS/Osiris/environments/ptahlog.conf
export OSIRIS_WORKING=/where/is/working

$OSIRIS/Osiris/bin/ptah.pl
