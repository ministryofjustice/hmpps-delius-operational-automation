#!/bin/bash

export DBID=$1
export CONNECT_TO_CATALOG=$2

. ~/.bash_profile

if [[ "${CONNECT_TO_CATALOG}" != "NOCATALOG" ]]
then
   CONNECT_TO_CATALOG="connect catalog ${CONNECT_TO_CATALOG}"
fi

rman <<EOF
set echo on
connect catalog ${CONNECT_TO_CATALOG};
set DBID ${DBID};
unregister database noprompt;
EOF
