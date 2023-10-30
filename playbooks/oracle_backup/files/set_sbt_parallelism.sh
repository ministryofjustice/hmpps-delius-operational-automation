#!/bin/bash

export ORACLE_SID=$1
export RESET_COMMAND=$2

export PATH=$PATH:/usr/local/bin;
export ORAENV_ASK=NO ;
. oraenv >/dev/null;

rman target / <<EOF 
${RESET_COMMAND}
exit
EOF
