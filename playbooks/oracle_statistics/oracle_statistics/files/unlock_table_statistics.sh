#!/bin/bash
#
#  Unlock Tables, except those supplied in the 2nd parameter
#

SCHEMA=$1
TABLE_LIST=$2

. ~/.bash_profile

echo "Do not unlock ${TABLE_LIST}"

sqlplus -s /nolog <<EOSQL
connect / as sysdba

WHENEVER SQLERROR EXIT FAILURE
SET SERVEROUT ON

DECLARE
   l_unlock_counter INTEGER := 0;
BEGIN
FOR t IN (SELECT table_name
          FROM   dba_tab_statistics
          WHERE  owner='${SCHEMA}'
          AND    stattype_locked IS NOT NULL
          AND    table_name NOT IN (${TABLE_LIST}))
LOOP
    EXECUTE IMMEDIATE 'BEGIN DBMS_STATS.unlock_table_stats(''${SCHEMA}'','''||t.table_name||'''); END;';
    l_unlock_counter := l_unlock_counter + 1;
END LOOP;
DBMS_OUTPUT.put_line('Unlocked '||l_unlock_counter||' table statistics.');
END;
/
EXIT
EOSQL
