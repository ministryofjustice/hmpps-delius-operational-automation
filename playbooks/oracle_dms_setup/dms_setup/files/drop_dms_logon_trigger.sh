#!/bin/bash
#
. ~/.bash_profile

sqlplus -s / as sysdba << EOF

WHENEVER SQLERROR EXIT FAILURE;

SET SERVEROUT ON
SET FEEDBACK OFF

DECLARE
   l_trigger_exists INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO   l_trigger_exists
    FROM   dba_triggers
    WHERE  owner = UPPER('${USER_SUPPORT_USER}')
    AND    trigger_name = UPPER('${DMS_USER}_restrict');

    IF l_trigger_exists > 0
    THEN
       EXECUTE IMMEDIATE 'DROP TRIGGER ${USER_SUPPORT_USER}.${DMS_USER}_restrict';
       DBMS_OUTPUT.put_line('Trigger dropped.');
    END IF;
END;
/

EXIT
EOF