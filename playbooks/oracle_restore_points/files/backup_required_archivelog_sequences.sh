#!/bin/bash
#
# Backup Archivelogs Required to Support Guaranteed Restore Point.
# Keep these for 1 year (unless explicitly dropped).   Note that KEEP backups cannot be written to the FRA.
# Note also that KEEP backups are outside of the normal backup routines and do not count towards
# backups of archivelogs which may be deleted.
#

LOWER_SEQUENCE=$1
UPPER_SEQUENCE=$2

. ~/.bash_profile

rman target / <<EORMAN

connect catalog ${CATALOG_CONNECTION}

set echo on

run {
  allocate channel rp1 device type sbt  parms='SBT_LIBRARY=${ORACLE_HOME}/lib/libosbws.so,  ENV=(OSB_WS_PFILE=${ORACLE_HOME}/dbs/osbws.ora)';
  backup archivelog sequence between ${LOWER_SEQUENCE} and ${UPPER_SEQUENCE} tag='RP_${RESTORE_POINT_NAME}' keep until time 'SYSDATE+365';
  }

EORMAN