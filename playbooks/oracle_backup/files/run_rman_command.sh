#!/bin/bash

export ORACLE_SID=$1
export CATALOG_CREDENTIALS=$2
export RMAN_COMMAND=$3

export PATH=$PATH:/usr/local/bin;
export ORAENV_ASK=NO ;
. oraenv >/dev/null;

if [[ "${CATALOG_CREDENTIALS}" != "NOCATALOG" ]]
then
   CONNECT_TO_CATALOG="connect catalog ${CATALOG_CREDENTIALS}"
fi

# Connect to RMAN and run a command
rman target / <<EOF
set echo on
${CONNECT_TO_CATALOG}
${RMAN_COMMAND}
EOF
