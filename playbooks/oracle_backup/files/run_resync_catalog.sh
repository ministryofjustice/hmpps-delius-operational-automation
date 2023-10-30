#!/bin/bash

. ~/.bash_profile

CONNECT_TO_CATALOG=${1}

rman target / <<EOF  | tee /tmp/rman_resync_catalog$$.log
set echo on
connect catalog ${CONNECT_TO_CATALOG}
resync catalog;
exit
EOF
