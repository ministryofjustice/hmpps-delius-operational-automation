#!/bin/bash

. ~/.bash_profile

sqlplus -s /  as sysdba <<EOF
WHENEVER SQLERROR EXIT FAILURE;
SET FEEDBACK OFF
SET HEADING OFF
SET SERVEROUT ON

DECLARE
    e_recovery_already_cancelled EXCEPTION;
    PRAGMA EXCEPTION_INIT (e_recovery_already_cancelled, -16136);  
BEGIN
    EXECUTE IMMEDIATE 'ALTER DATABASE RECOVER MANAGED STANDBY DATABASE CANCEL';
EXCEPTION
        WHEN e_recovery_already_cancelled
        THEN
            DBMS_OUTPUT.put_line('Recovery has already been cancelled.');
END;
/

EOF