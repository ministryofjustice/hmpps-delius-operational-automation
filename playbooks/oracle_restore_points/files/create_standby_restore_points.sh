#!/bin/bash


. ~/.bash_profile

sqlplus -s /  as sysdba <<EOF
WHENEVER SQLERROR EXIT FAILURE;
SET FEEDBACK OFF
SET HEADING OFF
SET SERVEROUT ON

DECLARE
  l_restore_point_exists  INTEGER;
  restore_point_exists    EXCEPTION;
  PRAGMA                  EXCEPTION_INIT(restore_point_exists,-38778);
  l_scn                   INTEGER:=${SCN};
BEGIN

SELECT COUNT(*)
INTO   l_restore_point_exists
FROM   V\$RESTORE_POINT
WHERE  name = '${RESTORE_POINT_NAME}';

IF l_restore_point_exists > 0 THEN
    DBMS_OUTPUT.PUT_LINE('ERROR: Restore Point ${RESTORE_POINT_NAME} already exists on '||SYS_CONTEXT('userenv','instance_name'));
    RAISE restore_point_exists;
END IF;

EXECUTE IMMEDIATE 'ALTER DATABASE RECOVER MANAGED STANDBY DATABASE CANCEL';

BEGIN
    IF l_scn > 0
    THEN
      EXECUTE IMMEDIATE 'CREATE RESTORE POINT ${RESTORE_POINT_NAME} AS OF SCN '||l_scn||' PRESERVE';
    ELSE
      EXECUTE IMMEDIATE 'CREATE RESTORE POINT ${RESTORE_POINT_NAME} GUARANTEE FLASHBACK DATABASE';
    END IF;
EXCEPTION
-- If there is any problem creating the restore point then
-- restart recovery before raising the error
WHEN others THEN
  EXECUTE IMMEDIATE 'ALTER DATABASE RECOVER MANAGED STANDBY DATABASE DISCONNECT FROM SESSION';
  RAISE;
END;

-- Restart recovery
EXECUTE IMMEDIATE 'ALTER DATABASE RECOVER MANAGED STANDBY DATABASE DISCONNECT FROM SESSION';

END;
/
EOF