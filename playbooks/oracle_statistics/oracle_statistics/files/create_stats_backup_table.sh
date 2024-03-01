#!/bin/bash
#
#   Create Table to Store Backup Statistics
#   This is in the DELIUS_USER_SUPPORT Schema
#

. ~/.bash_profile

sqlplus -s /nolog <<EOSQL
connect / as sysdba

WHENEVER SQLERROR EXIT FAILURE
SET FEEDBACK OFF
SET SERVEROUT ON

DECLARE
   table_exists EXCEPTION;
   PRAGMA EXCEPTION_INIT(table_exists,-20002);
BEGIN
   DBMS_STATS.create_stat_table (
       ownname => 'DELIUS_USER_SUPPORT'
      ,stattab => 'STATISTICS_BACKUP'
   );
EXCEPTION
   WHEN table_exists
   THEN
      DBMS_OUTPUT.put_line('STATISTICS_BACKUP table already exists.');
END;
/
EXIT
EOSQL