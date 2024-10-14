#!/bin/bash
#
#  Get the Names of Audited Interaction Archival Schemas Already Created

. ~/.bash_profile

sqlplus -L -S /nolog <<EOSQL
connect / as sysdba
SET PAGES 0
SET FEEDBACK OFF
SET ECHO OFF

SELECT username
FROM   dba_users
WHERE  username IN ('DELIUS_AUDIT_DMS_POOL')
;

EXIT
EOSQL