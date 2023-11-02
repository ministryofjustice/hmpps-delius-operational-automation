#!/bin/bash

. ~/.bash_profile

sqlplus -s /  as sysdba <<EOF
WHENEVER SQLERROR EXIT FAILURE;
SET FEEDBACK OFF
SET HEADING OFF
SET SERVEROUT ON

DECLARE
    e_database_busy EXCEPTION;
    PRAGMA EXCEPTION_INIT (e_database_busy, -1154);  
    e_database_open EXCEPTION;
    PRAGMA EXCEPTION_INIT (e_database_open, -1531);                

BEGIN
    EXECUTE IMMEDIATE 'ALTER DATABASE OPEN RESETLOGS';
EXCEPTION
        WHEN e_database_busy
        THEN
            DBMS_OUTPUT.put_line('Database is already opening.');
        WHEN e_database_open
        THEN
            DBMS_OUTPUT.put_line('Database is already open.');
END;
/
EOF

#  See SR 3-32867362321 : SIHA Database Mounted but Not Open at Reboot
#  Oracle Support recommend that the database is restarted using
#  srvctl following a flashback operation to ensure the oraagent 
#  has the correct state.

srvctl stop database -d $ORACLE_SID
srvctl start database -d $ORACLE_SID