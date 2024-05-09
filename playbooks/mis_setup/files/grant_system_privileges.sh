#!/bin/bash

. ~/.bash_profile

sqlplus -s / as sysdba << EOF
SET LINES 132
SET PAGES 0
SET FEEDBACK OFF
SET HEADING OFF
SET SERVEROUTPUT ON SIZE 1000000
WHENEVER SQLERROR EXIT FAILURE

DECLARE
  l_system_privileges CLOB := q'|$SYSPRIVSJSON|';

BEGIN

  -- By default the following system privileges are granted

  FOR r IN (SELECT 'GRANT '||syspriv||' TO ${SCHEMA_NAME}' statement_command
            FROM JSON_TABLE(
             (SELECT l_system_privileges FROM dual),'\$[*]' COLUMNS (syspriv VARCHAR2(100) PATH '\$'))
           ) LOOP

    DBMS_OUTPUT.put_line(r.statement_command);
    EXECUTE IMMEDIATE r.statement_command;

  END LOOP;

END;
/
EOF