#!/bin/bash
#
#  Ensure Database Statistics Preferences are Set As Expected
#

SCHEMA_NAME=$1

. ~/.bash_profile

sqlplus -s /nolog <<EOSQL
connect / as sysdba

WHENEVER SQLERROR EXIT FAILURE
SET FEEDBACK OFF
SET SERVEROUT ON

DECLARE
   /*
       For statistics gathering we require:
          * OBJECT_STATS - Table and Index Statistics
          * SYNOPSES     - Used for Global Incremental Statistics on AUDITED_INTERACTION
       We do not required READ_TIME_STATS as only available on Engineered Systems
   */
   l_existing_stat_category   VARCHAR2(100);
   l_target_stat_category     CONSTANT VARCHAR2(100) := 'OBJECT_STATS, SYNOPSES';
BEGIN
   l_existing_stat_category := DBMS_STATS.get_prefs(pname  => 'STAT_CATEGORY');
   IF l_existing_stat_category != l_target_stat_category
   THEN
      DBMS_STATS.set_global_prefs(pname  => 'STAT_CATEGORY', pvalue => l_target_stat_category);
      DBMS_OUTPUT.put_line('Changed STAT_CATEGORY to '||l_target_stat_category);
   END IF;
END;
/
EXIT
EOSQL