#!/bin/bash
#
#  Ensure that a sensible restore point name is used.
#  Avoid:
#    (1)  Reserved Keywords
#    (2)  Existing Restore Point Names
#
#  The reason for this check, rather than letting the task fail directly,
#  is that sometimes the reserved keyword is allowed for CREATE RESTORE POINT
#  but not for FLASHBACK TO RESTORE POINT thus resulting in a restore point
#  being created which cannot be used.   This check pre-empts this by
#  preventing such a restore point being created in the first place.
#

. ~/.bash_profile

sqlplus -s /  as sysdba <<EOF
WHENEVER SQLERROR EXIT FAILURE;
SET FEEDBACK OFF
SET HEADING OFF
SET SERVEROUT ON

DECLARE
  l_restore_point_exists  INTEGER;
  duplicate_restore_point EXCEPTION;
  PRAGMA                  EXCEPTION_INIT(duplicate_restore_point,-38778);
  l_reserved_keyword      INTEGER;
  reserved_word           EXCEPTION;
  PRAGMA                  EXCEPTION_INIT(reserved_word,-904); 
BEGIN
  
  SELECT COUNT(*)
  INTO   l_restore_point_exists
  FROM   V\$RESTORE_POINT
  WHERE  UPPER(name) = UPPER('${RESTORE_POINT_NAME}');
  
  IF l_restore_point_exists > 0 THEN
    DBMS_OUTPUT.put_line('ERROR: Duplicate restore point ${RESTORE_POINT_NAME} already exists.');
    RAISE duplicate_restore_point;
  END IF;

  SELECT COUNT(*)
  INTO   l_reserved_keyword
  FROM   V\$RESERVED_WORDS
  WHERE  UPPER(keyword) = '${RESTORE_POINT_NAME}';

  IF l_reserved_keyword > 0 THEN
    DBMS_OUTPUT.put_line('ERROR: ${RESTORE_POINT_NAME} is a reserved word and cannot be used.');
    RAISE reserved_word;
  END IF;

END;
/
EOF