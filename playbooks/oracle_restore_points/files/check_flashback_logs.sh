#!/bin/bash

. ~/.bash_profile

sqlplus -s /  as sysdba <<EOF
WHENEVER SQLERROR EXIT FAILURE;
SET FEEDBACK OFF
SET HEADING OFF
SET SERVEROUT ON

DECLARE
    e_old_date EXCEPTION;
    PRAGMA EXCEPTION_INIT (e_old_date, -2002);   
    l_restore_datetime_exists  INTEGER;

BEGIN
    SELECT COUNT(*)
    INTO l_restore_datetime_exists
    FROM v\$flashback_database_log
    WHERE TO_DATE('${RESTORE_DATE_TIME}','DD-MM-YYYY-HH24-MI-SS') >= oldest_flashback_time;

    IF l_restore_datetime_exists = 0
    THEN
        RAISE e_old_date;
    END IF;

EXCEPTION
    WHEN e_old_date
    THEN
        DBMS_OUTPUT.PUT_LINE('ERROR: Restore Datetime ${RESTORE_DATE_TIME} is earlier than oldest flashback time');
        RAISE;
END;
/
EOF