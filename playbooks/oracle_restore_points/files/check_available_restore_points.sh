#!/bin/bash

. ~/.bash_profile

sqlplus -s /  as sysdba <<EOF
WHENEVER SQLERROR EXIT FAILURE;
SET FEEDBACK OFF
SET HEADING OFF
SET SERVEROUT ON

DECLARE
  l_restore_point_exists      INTEGER;
  restore_point_not_exists    EXCEPTION;
  PRAGMA                      EXCEPTION_INIT(restore_point_not_exists,-38780);
BEGIN

  SELECT COUNT(*)
  INTO   l_restore_point_exists
  FROM   V\$RESTORE_POINT
  WHERE  name = '${RESTORE_POINT_NAME}';

  IF l_restore_point_exists = 0 THEN
      DBMS_OUTPUT.PUT_LINE('ERROR: Restore Point ${RESTORE_POINT_NAME} does not exist on '||SYS_CONTEXT('userenv','instance_name'));
      RAISE restore_point_not_exists;
  END IF;

END;
/
EOF