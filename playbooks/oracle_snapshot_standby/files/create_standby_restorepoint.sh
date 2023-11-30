#!/bin/bash

. ~/.bash_profile

RESTORE_POINT_NAME=$1
SCN=$2

sqlplus -s /  as sysdba <<EOF
WHENEVER SQLERROR EXIT FAILURE;
SET FEEDBACK OFF
SET HEADING OFF
SET SERVEROUT ON

DECLARE
  l_restore_point_exists  INTEGER;
BEGIN

SELECT COUNT(*)
INTO   l_restore_point_exists
FROM   V\$RESTORE_POINT
WHERE  name = '${RESTORE_POINT_NAME}';

IF l_restore_point_exists > 0 
THEN
    -- Do nothing if restore point already exists
    DBMS_OUTPUT.PUT_LINE('Restore Point ${RESTORE_POINT_NAME} already exists on '||SYS_CONTEXT('userenv','instance_name'));
ELSE

    EXECUTE IMMEDIATE 'ALTER DATABASE RECOVER MANAGED STANDBY DATABASE CANCEL';

    BEGIN
        -- Restore points created as of a specific SCN cannot be guaranteed
        EXECUTE IMMEDIATE 'CREATE RESTORE POINT ${RESTORE_POINT_NAME} AS OF SCN ${SCN}';
    EXCEPTION
    -- If there is any problem creating the restore point then
    -- restart recovery before raising the error
    WHEN others THEN
      EXECUTE IMMEDIATE 'ALTER DATABASE RECOVER MANAGED STANDBY DATABASE DISCONNECT FROM SESSION';
      RAISE;
    END;

    -- Restart recovery
    EXECUTE IMMEDIATE 'ALTER DATABASE RECOVER MANAGED STANDBY DATABASE DISCONNECT FROM SESSION';
END IF;

-- Remove Replicated Restore Points matching the Primary
-- as we expect all restore points to have the same name
SELECT COUNT(*)
INTO   l_restore_point_exists
FROM   V\$RESTORE_POINT
WHERE  name = '${RESTORE_POINT_NAME}_PRIMARY'
AND    replicated = 'YES';

IF l_restore_point_exists > 0 
THEN
   DBMS_OUTPUT.put_line('Dropping replicated restore point ${RESTORE_POINT_NAME}_PRIMARY');
   EXECUTE IMMEDIATE 'DROP RESTORE POINT ${RESTORE_POINT_NAME}_PRIMARY';
END IF;

END;
/
EOF