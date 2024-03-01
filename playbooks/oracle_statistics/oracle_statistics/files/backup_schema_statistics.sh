#!/bin/bash
#
#  Backup Statistics for a Given Schema
#

SCHEMA_NAME=$1
BACKUP_IDENTIFIER=$2

. ~/.bash_profile

sqlplus -s /nolog <<EOSQL
connect / as sysdba

WHENEVER SQLERROR EXIT FAILURE
SET SERVEROUT ON

DECLARE
   l_schema  dba_users.username%TYPE;
BEGIN
   SELECT MAX(username) username
   INTO   l_schema
   FROM   dba_users
   WHERE  username = '${SCHEMA_NAME}';

   IF l_schema = '${SCHEMA_NAME}'
   THEN

      DBMS_STATS.export_schema_stats (
         ownname => '${SCHEMA_NAME}'
         ,statid  => '${BACKUP_IDENTIFIER}'
         ,statown => 'DELIUS_USER_SUPPORT'
         ,stattab => 'STATISTICS_BACKUP'
      );

      DBMS_OUTPUT.put_line('Backed up statistics for ${SCHEMA_NAME}.');
   END IF;
END;
/
EXIT
EOSQL