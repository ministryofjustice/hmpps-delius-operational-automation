#!/bin/bash
#
#  Remove any Existing Backup Statistics with BACKUP_IDENTIFIER
#

BACKUP_IDENTIFIER=$1

. ~/.bash_profile

sqlplus -s /nolog <<EOSQL
connect / as sysdba

WHENEVER SQLERROR EXIT FAILURE
SET FEEDBACK ON
SET SERVEROUT ON
SET HEADING OFF
SET PAGES 0

DELETE
FROM   delius_user_support.statistics_backup
WHERE  statid = '${BACKUP_IDENTIFIER}';

COMMIT;

EXIT
EOSQL