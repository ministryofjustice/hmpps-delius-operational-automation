#!/bin/bash

export ORACLE_SID=$1
export CATALOG_CREDENTIALS=$2
export DBID=$3

export PATH=$PATH:/usr/local/bin;
export ORAENV_ASK=NO ;
. oraenv >/dev/null;

export NLS_DATE_FORMAT="YYYY-MM-DD HH24:MI:SS"

if [[ "${CATALOG_CREDENTIALS}" != "NOCATALOG" ]]
then
   CONNECT_TO_CATALOG="connect catalog ${CATALOG_CREDENTIALS}"
fi

# Connect to RMAN and find the CURRENT incarnation of the database
rman target / <<EOF | awk -v DBID="${DBID}" '$4~DBID&&$5~/CURRENT/{print $7,$8}'
set echo on
${CONNECT_TO_CATALOG}
list incarnation of database;
EOF
