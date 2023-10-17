#!/bin/bash

. ~/.bash_profile

sqlplus -s /  as sysdba <<EOF
SET LINES 1000
SET PAGES 0
SET FEEDBACK OFF
SET HEADING OFF
SET SERVEROUT ON
WHENEVER SQLERROR EXIT FAILURE

BEGIN

  FOR session_info IN (SELECT 'ALTER SYSTEM DISCONNECT SESSION '||''''||sid||','||serial#||''''||' IMMEDIATE' kill_sessions
                       FROM V\$SESSION
                       WHERE type != 'BACKGROUND'
                       AND username NOT IN ('PUBLIC','SYS')
                       AND sid NOT IN (SELECT SYS_CONTEXT ('userenv', 'sid') FROM DUAL))
  LOOP
    BEGIN
      EXECUTE IMMEDIATE session_info.kill_sessions;
    EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE = -00030
      OR SQLCODE = -00031
      THEN
        DBMS_OUTPUT.PUT_LINE('DATABASE SESSION MARKED FOR KILL');
      ELSE
        RAISE;
      END IF;
    END;
  END LOOP;

END;
/
EXIT
EOF