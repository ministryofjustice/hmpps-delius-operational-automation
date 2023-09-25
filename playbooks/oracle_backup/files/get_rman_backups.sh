#!/bin/bash

export CATALOG_CREDENTIALS=$1
export NUM_OF_DAYS_BACK_TO_VALIDATE="${2:-0}"

. ~/.bash_profile

if [[ "${CATALOG_CREDENTIALS}" != "NOCATALOG" ]]
then
   CONNECT_TO_CATALOG="connect catalog ${CATALOG_CREDENTIALS}"
fi

# Get list of RMAN backups from the Catalog; merge the Availability and Handle Lines
# and return the HANDLE, the BACKUPPIECE ID and the AVAILABILITY status for each backup piece
# (filter out all other output)
rman target / <<EOF | awk '/Handle:/{print $0,PREV;}{PREV=$0}' | awk '{print $2,$7,$9}'
${CONNECT_TO_CATALOG};
list backup completed after 'SYSDATE-${NUM_OF_DAYS_BACK_TO_VALIDATE}';
EOF
