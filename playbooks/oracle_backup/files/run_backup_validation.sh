#!/bin/bash

export ORACLE_SID=$1
export START_SCN=$2
export PARALLELISM=$3
export VALIDATE_INCREMENTAL_COMMAND=$4
export VALIDATE_ARCHIVELOG_COMMAND=$5
export CATALOG_CREDENTIALS=$6
export END_SCN=$7

export PATH=$PATH:/usr/local/bin;
export ORAENV_ASK=NO ;
. oraenv >/dev/null;

VALIDATE_RESTORE_CONTROLFILE_COMMAND="restore controlfile validate;"
VALIDATE_RESTORE_DATABASE_COMMAND="restore database validate;"
VALIDATE_RESTORE_ARCHIVELOG_COMMAND="restore archivelog from scn ${START_SCN} validate;"

# Check end SCN 
if [[ ! -z "${END_SCN}" ]]
then
    VALIDATE_RESTORE_CONTROLFILE_COMMAND="restore controlfile until scn ${END_SCN} validate;"
    VALIDATE_RESTORE_DATABASE_COMMAND="restore database until scn ${END_SCN} validate;"
    VALIDATE_RESTORE_ARCHIVELOG_COMMAND="restore archivelog from scn ${START_SCN} until scn ${END_SCN} validate;"
fi

# We perform 3 different validations:
# (1) Validate that a control file may be restored.
# (2) Validate that the database may be restored.
# (3) Validate that incremental backupsets may be restored (pass in the validation command)
# (4) Validate that archive log backupsets may be restored after the given SCN (pass in the validation command)
# (5) Validate that archive logs may be restored after the given SCN (which should be the start SCN for the database backup)
#

if [[ "${CATALOG_CREDENTIALS}" != "NOCATALOG" ]]
then
   CONNECT_TO_CATALOG="connect catalog ${CATALOG_CREDENTIALS}"
fi

rman target / <<EOF  | tee /tmp/rman_validation$$.log
set echo on
${CONNECT_TO_CATALOG}
configure device type 'SBT_TAPE' parallelism ${PARALLELISM};
${VALIDATE_RESTORE_CONTROLFILE_COMMAND}
${VALIDATE_RESTORE_DATABASE_COMMAND}
${VALIDATE_INCREMENTAL_COMMAND}
${VALIDATE_ARCHIVELOG_COMMAND}
${VALIDATE_RESTORE_ARCHIVELOG_COMMAND}
exit
EOF
