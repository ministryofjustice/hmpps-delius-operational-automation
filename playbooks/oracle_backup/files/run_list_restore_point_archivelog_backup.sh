#!/bin/bash
#
#  Find Archivelog Sequences associated with a Restore Point
#  but only if this is the most recent Archivelog Backup.
#  (We take archive log backups when we create a new Restore Point to
#   ensure that the restore point will be usable beyond the normal
#   retention time of the archive log backups.  However we wish to
#   exclude these archive logs from routine backup validation since
#   they may be ahead of the latest normal archive log backup
#   and would appear as if there is a gap in archive log backups.
#   This only applies if the Restore Point backup is the very latest
#   backup as otherwise it will have been absorbed into the
#   routine archive log backups, and there will not be a gap.)

export ORACLE_SID=$1
export START_SCN=$2
export CONNECT_TO_CATALOG=$3
export END_SCN=$4

export PATH=$PATH:/usr/local/bin;
export ORAENV_ASK=NO ;
. oraenv >/dev/null;

export NLS_DATE_FORMAT="YYYY-MM-DD HH24:MI:SS"

RMAN_CMD="list backup of archivelog from scn ${START_SCN} summary;"

# Check end scn
if [[ ! -z "${END_SCN}" ]]
then
    RMAN_CMD="list backup of archivelog from scn ${START_SCN} until scn ${END_SCN} summary;"
fi

LATEST_BACKUP_TAG=$(
rman target / <<EOF | grep SBT_TAPE | tail -1 | awk '{print $NF}'
set echo on
connect catalog ${CONNECT_TO_CATALOG}
${RMAN_CMD}
exit
EOF
)

# If the most recent backup is a Restore Point backup (indicated by an RP_ prefix)
# then list all of the archive logs included in that backup.
# If it is not a Restore Point backup then return nothing.
if [[ ${LATEST_BACKUP_TAG} =~ ^RP_ ]];
then
   rman target / <<EOF
   set echo on
   connect catalog ${CONNECT_TO_CATALOG}
   list backup of archivelog all tag ${LATEST_BACKUP_TAG};
   exit
EOF
fi