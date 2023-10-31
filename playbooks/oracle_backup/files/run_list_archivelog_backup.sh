#!/bin/bash

export ORACLE_SID=$1
export START_SCN=$2
export CATALOG_CREDENTIALS=$3
export END_SCN=$4

export PATH=$PATH:/usr/local/bin;
export ORAENV_ASK=NO ;
. oraenv >/dev/null;

export NLS_DATE_FORMAT="YYYY-MM-DD HH24:MI:SS"

RMAN_CMD="list backup of archivelog from scn ${START_SCN};"

# Check end scn
if [[ ! -z "${END_SCN}" ]] 
then
    RMAN_CMD="list backup of archivelog from scn ${START_SCN} until scn ${END_SCN};"
fi

if [[ "${CATALOG_CREDENTIALS}" != "NOCATALOG" ]]
then
   CONNECT_TO_CATALOG="connect catalog ${CATALOG_CREDENTIALS}"
fi

rman target / <<EOF
set echo on
${CONNECT_TO_CATALOG}
${RMAN_CMD}
exit
EOF
