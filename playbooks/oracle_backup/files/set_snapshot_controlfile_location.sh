#!/bin/bash
#  Place the Snapshot Controlfile in the FLASH Disk Group.
#  Note that we must define a complete path, not just to top level Disk Group.
#  (No error would be thrown here, but later backups will not work without a full path)

SNAPSHOT_CONTROLFILE_NAME=$1

. ~/.bash_profile

rman target / <<EOF
configure snapshot controlfile name to '${SNAPSHOT_CONTROLFILE_NAME}';
EOF