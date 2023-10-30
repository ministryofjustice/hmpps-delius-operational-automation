#!/bin/bash

export ORACLE_SID=$1
export CATALOG_CREDENTIALS=$2
export END_SCN=$3

# Check Oracle SID exists
/usr/local/bin/dbhome ${ORACLE_SID}

if [[ $? -gt 0 ]]
then
   echo "Invalid Oracle SID"
   exit 123
fi

RMAN_CMD="restore database preview;"

# Check restore datetime exists
if [[ ! -z "${END_SCN}" ]]
then
   RMAN_CMD="restore database until scn ${END_SCN} preview;"
fi

export PATH=$PATH:/usr/local/bin;
export ORAENV_ASK=NO ;
. oraenv >/dev/null;

if [[ "${CATALOG_CREDENTIALS}" != "NOCATALOG" ]]
then
   CONNECT_TO_CATALOG="connect catalog ${CATALOG_CREDENTIALS}"
fi

rman target /  <<EOF 
set echo on
${CONNECT_TO_CATALOG}
${RMAN_CMD}
exit
EOF
