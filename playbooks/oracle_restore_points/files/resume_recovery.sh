#!/bin/bash

. ~/.bash_profile

sqlplus -s /  as sysdba <<EOF
WHENEVER SQLERROR EXIT FAILURE;
SET FEEDBACK OFF
SET HEADING OFF
SET SERVEROUT ON

DECLARE
    e_flashback_in_progress EXCEPTION;
    PRAGMA EXCEPTION_INIT (e_flashback_in_progress, -1153);  
BEGIN
    EXECUTE IMMEDIATE 'ALTER DATABASE RECOVER MANAGED STANDBY DATABASE DISCONNECT';
EXCEPTION
        WHEN e_flashback_in_progress
        THEN
            DBMS_OUTPUT.put_line('Recovery is already in progress.');
END;
/

EXIT;
EOF