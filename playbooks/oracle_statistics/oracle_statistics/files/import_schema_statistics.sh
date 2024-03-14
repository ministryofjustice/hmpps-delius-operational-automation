#!/bin/bash
#
#  Import Statistics for a Given Schema
#

SCHEMA_NAME=$1
BACKUP_IDENTIFIER=$2

. ~/.bash_profile

sqlplus -s /nolog <<EOSQL
connect / as sysdba

WHENEVER SQLERROR EXIT FAILURE
SET SERVEROUT ON

DECLARE
   l_unlocked_table_count  INTEGER;
BEGIN

   -- Only import statistics if there is at least one table
   -- where statistics are unlocked and has importable
   -- statistics in the backup table.
   -- Otherwise DBMS_STATS throws an error.

   SELECT COUNT(*) unlocked_tables
   INTO   l_unlocked_table_count
   FROM   dba_tab_statistics s
   WHERE  s.owner = '${SCHEMA_NAME}'
   AND    ( s.stattype_locked IS NULL 
            OR s.stattype_locked != 'ALL' )
   AND EXISTS (SELECT 1
               FROM   delius_user_support.statistics_backup b
               WHERE  b.statid = '${BACKUP_IDENTIFIER}'
               AND    b.c5 = s.owner
               AND    b.c1 = s.table_name);

   IF l_unlocked_table_count > 0
   THEN

      -- NO_INVALIDATE is set FALSE as we want to see impact
      -- of statistics changes immediately
      DBMS_STATS.import_schema_stats(
          ownname=>'${SCHEMA_NAME}'
         ,stattab=>'STATISTICS_BACKUP'
         ,statid=>'${BACKUP_IDENTIFIER}'
         ,statown=>'DELIUS_USER_SUPPORT'
         ,no_invalidate=>FALSE
         ,force=>FALSE
         ,stat_category=>'OBJECT_STATS,SYNOPSES'
      );

      DBMS_OUTPUT.put_line('Imported statistics for ${SCHEMA_NAME}.');
   END IF;
END;
/
EXIT
EOSQL