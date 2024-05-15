#!/bin/bash

export ORACLE_SID=$1
export PATH=$PATH:/usr/local/bin;
export ORAENV_ASK=NO ;
. oraenv >/dev/null;

rman target / <<EOF
show channel;
exit
EOF
