#!/bin/bash

export PATH=$PATH:/usr/local/bin; 
export ORACLE_SID=+ASM; 
export ORAENV_ASK=NO ; 
. oraenv >/dev/null;

export COMPATIBLE_TYPE=$1
export DISK_GROUP=$2
export VERSION=$3

sqlplus -s /  as sysasm <<EOF
SET LINES 1000
SET PAGES 0
SET FEEDBACK OFF
SET HEADING OFF
WHENEVER SQLERROR EXIT FAILURE
ALTER DISKGROUP ${DISK_GROUP} SET ATTRIBUTE '${COMPATIBLE_TYPE}' = '${VERSION}';
EXIT
EOF