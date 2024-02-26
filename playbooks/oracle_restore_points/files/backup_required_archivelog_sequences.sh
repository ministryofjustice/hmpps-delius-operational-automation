#!/bin/bash
#
# Backup Archivelogs Required to Support Guaranteed Restore Point.
# Keep these for 1 year (unless explicitly dropped).   Note that KEEP backups cannot be written to the FRA.
# Note also that KEEP backups are outside of the normal backup routines and do not count towards
# backups of archivelogs which may be deleted.
#
get_rman_password () {
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ASSUME_ROLE_NAME}"
  SESSION="catalog-ansible"
  CREDS=$(aws sts assume-role --role-arn "${ROLE_ARN}" --role-session-name "${SESSION}"  --output text --query "Credentials.[AccessKeyId,SecretAccessKey,SessionToken]")
  export AWS_ACCESS_KEY_ID=$(echo "${CREDS}" | tail -1 | cut -f1)
  export AWS_SECRET_ACCESS_KEY=$(echo "${CREDS}" | tail -1 | cut -f2)
  export AWS_SESSION_TOKEN=$(echo "${CREDS}" | tail -1 | cut -f3)
  SECRET_ARN="arn:aws:secretsmanager:eu-west-2:${SECRET_ACCOUNT_ID}:secret:${SECRET}"
  RMANPASS=$(aws secretsmanager get-secret-value --secret-id "${SECRET_ARN}" --query SecretString --output text | jq -r .rcvcatowner)
}

LOWER_SEQUENCE=$1
UPPER_SEQUENCE=$2

. ~/.bash_profile

if [[ ! -z "$CATALOG" ]] 
then
   get_rman_password
   CONNECT_CATALOG="connect catalog rcvcatowner/${RMANPASS}@${CATALOG}"
fi

rman target / <<EORMAN

$CONNECT_CATALOG

set echo on

run {
  allocate channel rp1 device type sbt  parms='SBT_LIBRARY=${ORACLE_HOME}/lib/libosbws.so,  ENV=(OSB_WS_PFILE=${ORACLE_HOME}/dbs/osbws.ora)';
  backup archivelog sequence between ${LOWER_SEQUENCE} and ${UPPER_SEQUENCE} tag='RP_${RESTORE_POINT_NAME}' keep until time 'SYSDATE+365';
  }

EORMAN