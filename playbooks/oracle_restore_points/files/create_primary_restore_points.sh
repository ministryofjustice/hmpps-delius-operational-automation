#!/bin/bash

. ~/.bash_profile

sqlplus -s /  as sysdba <<EOF
WHENEVER SQLERROR EXIT FAILURE;
SET FEEDBACK OFF
SET HEADING OFF
SET SERVEROUT ON

-- Switch Logs a few times to ensure that any Archive Logs which are needed 
-- for flashing back are minimal

ALTER SYSTEM SWITCH LOGFILE;
/
/

DECLARE
  l_restore_point_exists  INTEGER;
  restore_point_exists    EXCEPTION;
  PRAGMA                  EXCEPTION_INIT(restore_point_exists,-38778);
  l_restore_date_time     VARCHAR2(30):='${RESTORE_DATE_TIME}';
BEGIN

  DBMS_SESSION.sleep(2);

  SELECT COUNT(*)
  INTO   l_restore_point_exists
  FROM   V\$RESTORE_POINT
  WHERE  name = '${RESTORE_POINT_NAME}';

  IF l_restore_point_exists > 0 THEN
      DBMS_OUTPUT.PUT_LINE('ERROR: Restore Point ${RESTORE_POINT_NAME} already exists on '||SYS_CONTEXT('userenv','instance_name'));
      RAISE restore_point_exists;
  END IF;

  IF l_restore_date_time IS NOT NULL
  THEN
    EXECUTE IMMEDIATE q'[CREATE RESTORE POINT ${RESTORE_POINT_NAME} AS OF TIMESTAMP TO_TIMESTAMP(']'||l_restore_date_time||q'[','DD-MM-YYYY-HH24-MI-SS') PRESERVE]';
  ELSE
    EXECUTE IMMEDIATE 'CREATE RESTORE POINT ${RESTORE_POINT_NAME} GUARANTEE FLASHBACK DATABASE';
  END IF;

END;
/
EOF