#!/bin/bash
#
#  Lock Statistics on Z_* Tables
#
#  These tables are created by scripts for temporary use.
#  Do not waste resources gathering statistics on tables
#  which are not used as part of normal operations.
#

SCHEMA=$1

. ~/.bash_profile

sqlplus -s /nolog <<EOSQL
connect / as sysdba

WHENEVER SQLERROR EXIT FAILURE
SET SERVEROUT ON
SET FEEDBACK OFF

DECLARE
   l_table_counter INTEGER := 0;
BEGIN
   FOR t IN (SELECT     t.table_name
             FROM       dba_tables t
             INNER JOIN dba_tab_statistics s
             ON         t.owner = s.owner
             AND        t.table_name = s.table_name
             AND        s.stattype_locked IS NULL
             WHERE      t.owner = '${SCHEMA}'
             AND        t.table_name LIKE 'Z_%')
   LOOP
      EXECUTE IMMEDIATE 'BEGIN DBMS_STATS.lock_table_stats(''${SCHEMA}'','''||t.table_name||'''); END;';
      l_table_counter := l_table_counter + 1;
   END LOOP;
   DBMS_OUTPUT.put_line('Statistics Locked on '||l_table_counter||' tables.');
END;
/
EXIT
EOSQL