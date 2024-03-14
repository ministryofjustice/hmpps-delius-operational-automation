#!/bin/bash
#
#  Lock Statistics on Tables With No Segments.
#
#  Tables without segments are empty but it is assumed that
#  they will not always be empty (otherwise why create them?!)
#  So do not attempt to gather statistics on them as at their
#  unpopulated state will not be reflective of normal use.
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
   FOR t IN (SELECT     t.table_name,ds.segment_name,s.stattype_locked
             FROM       dba_tables t
             INNER JOIN dba_tab_statistics s
             ON         t.owner = s.owner
             AND        t.table_name = s.table_name
             AND        s.stattype_locked IS NULL
             LEFT JOIN  dba_segments ds 
             ON         t.owner = ds.owner
             AND        t.table_name = ds.segment_name
             AND        ds.segment_type IN ('TABLE','TABLE PARTITION')
             WHERE      ds.segment_name IS NULL
             AND        t.owner = '${SCHEMA}')
   LOOP
      EXECUTE IMMEDIATE 'BEGIN DBMS_STATS.lock_table_stats(''${SCHEMA}'','''||t.table_name||'''); END;';
      l_table_counter := l_table_counter + 1;
   END LOOP;
   DBMS_OUTPUT.put_line('Statistics Locked on '||l_table_counter||' tables.');
END;
/
EXIT
EOSQL