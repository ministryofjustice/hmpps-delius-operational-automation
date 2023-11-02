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
    EXECUTE IMMEDIATE 'FLASHBACK DATABASE TO RESTORE POINT ${RESTORE_POINT_NAME}';
EXCEPTION
        WHEN e_flashback_in_progress
        THEN
            DBMS_OUTPUT.put_line('Flashback or recovery is already in progress.');
END;
/
EOF