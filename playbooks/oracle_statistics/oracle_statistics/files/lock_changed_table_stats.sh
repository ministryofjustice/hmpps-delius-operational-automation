#!/bin/bash
#
#  Lock Statistics on Tables Which Have Been Changed Recently.
#
#  These might be brand new tables or tables with new or removed columns.
#  If the change has been made recently then the data in the table may
#  not yet be sufficiently representative of the table once it enters
#  normal use.   Therefore we do not make any changes to the existing
#  statistics on this table to avoid changing access paths.
#
#  If it is a brand new table it may have no statistics, unless those
#  were set on creation.   Locking statistics ensures that dynamic
#  sampling will be used until the table has been in existence long
#  enough that the data content may be considered more representative.
#

SCHEMA=$1
DAYS_THRESHOLD=$2

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
             INNER JOIN dba_objects o 
             ON         t.owner = o.owner
             AND        t.table_name = o.object_name
             AND        o.object_type = 'TABLE'
             AND        t.owner       = '${SCHEMA}'
             AND        (SYSDATE-TO_DATE(o.timestamp, 'YYYY-MM-DD-HH24:MI:SS')) < ${DAYS_THRESHOLD}
             INNER JOIN dba_tab_statistics s
             ON         o.owner = s.owner
             AND        o.object_name = s.table_name
             AND        s.stattype_locked IS NULL)
   LOOP
      EXECUTE IMMEDIATE 'BEGIN DBMS_STATS.lock_table_stats(''${SCHEMA}'','''||t.table_name||'''); END;';
      l_table_counter := l_table_counter + 1;
   END LOOP;
   DBMS_OUTPUT.put_line('Statistics Locked on '||l_table_counter||' tables.');
END;
/
EXIT
EOSQL