#!/bin/bash

pod2markdown ../Osiris/lib/Osiris.pm      > ./pod/Osiris.md
pod2markdown ../Osiris/lib/Osiris/AAF.pm  > ./pod/AAF.md
pod2markdown ../Osiris/lib/Osiris/App.pm  > ./pod/App.md
pod2markdown ../Osiris/lib/Osiris/Form.pm > ./pod/Form.md
pod2markdown ../Osiris/lib/Osiris/Job.pm  > ./pod/Job.md
pod2markdown ../Osiris/lib/Osiris/Test.pm > ./pod/Test.md
pod2markdown ../Osiris/lib/Osiris/User.pm > ./pod/User.md

pod2markdown ../Osiris/bin/ptah.pl        > ./pod/ptah.md
