#!/bin/bash
# Find the path to the snapshot control file

. ~/.bash_profile

rman target / <<EOF
show snapshot controlfile name;
EOF
