#!/bin/bash
#  Supply the Statement and Privilege Audit Options in JSON format
#  For example:
#       {
#        "StatementOptions"      : [ "ALTER ANY PROCEDURE","ALTER ANY TABLE" ],
#        "PrivilegeOptions"      : [ "DROP_USER","DROP PROFILE" ]
#       }

AUDITJSON="$1"

. ~/.bash_profile

sqlplus -s / as sysdba << EOSQL
SET SERVEROUTPUT ON SIZE UNLIMITED
SET FEEDBACK OFF

BEGIN

   -- Add any missing statement and privilege audit options and remove any unrequested statement audit options
   -- unless these are defined as system privilege audit options
   -- (We ignore CREATE SESSION as this is treated separately below)
   FOR s IN (
       WITH json_audit
          AS
          (
          SELECT q'|$AUDITJSON|' data FROM dual
          )     
          SELECT *
          FROM (
          SELECT -- Statement Auditing
               CASE WHEN dsao.audit_option IS NULL THEN 'AUDIT '||js.option_name
                    WHEN js.option_name IS NULL AND dsao.audit_option != 'CREATE SESSION' THEN 'NOAUDIT '||dsao.audit_option
                    ELSE NULL
                    END statement_command
          FROM json_audit CROSS JOIN JSON_TABLE(data, '\$.StatementOptions[*]' COLUMNS (option_name VARCHAR2(100) PATH '\$')) js
          FULL OUTER JOIN dba_stmt_audit_opts dsao
          ON    js.option_name = dsao.audit_option 
          UNION
          SELECT -- Privilege Auditing
               CASE WHEN dpao.privilege IS NULL THEN 'AUDIT '||jp.option_name
                    WHEN jp.option_name IS NULL AND dpao.privilege != 'CREATE SESSION' THEN 'NOAUDIT '||dpao.privilege
                    ELSE NULL
                    END
          FROM json_audit CROSS JOIN JSON_TABLE(data, '\$.PrivilegeOptions[*]' COLUMNS (option_name VARCHAR2(100) PATH '\$')) jp
          FULL OUTER JOIN dba_priv_audit_opts dpao
          ON    jp.option_name = dpao.privilege 
          )
          WHERE statement_command IS NOT NULL )
    LOOP
           DBMS_OUTPUT.put_line(s.statement_command);
           EXECUTE IMMEDIATE s.statement_command;
    END LOOP;

  -- If we do not wish to audit create session events by users then the usernames should be specified under NoAuditSessions
  -- Note that we cannot use NOAUDIT CREATE SESSION with individual users.   Instead we must apply that at database level
  -- and then apply AUDIT CREATE SESSION to all users NOT listed under NoAuditSessions.
  -- This is done by the following code.   Note that if NoAuditSessions does not include any valid database users then a
  -- simple AUDIT CREATE SESSION at database level may be used instead.
  -- Note that we cannot explicitly Create Session by SYS as this may not be disabled.
  FOR p IN (
     WITH json_audit
     AS
     (
     SELECT q'|$AUDITJSON|' data FROM dual
     ),
     noaudit_sessions(row_count)
     AS (
     SELECT COUNT(*)
     FROM json_audit ja CROSS JOIN JSON_TABLE(data, '\$.NoAuditSessions[*]' COLUMNS (username VARCHAR2(100) PATH '\$')) jp
     INNER JOIN dba_users u
     ON jp.username = u.username
     )
     SELECT CASE WHEN row_count = 0 THEN 'AUDIT CREATE SESSION'
          ELSE 'NOAUDIT CREATE SESSION'  END audit_session_command
     FROM noaudit_sessions
     UNION ALL
     SELECT 
     CASE 
          WHEN jp.username IS NULL AND u.username IS NOT NULL AND dsao.user_name IS NULL
          THEN
               'AUDIT CREATE SESSION BY '||u.username
          ELSE NULL END audit_session_command    
     FROM json_audit ja CROSS JOIN JSON_TABLE(data, '\$.NoAuditSessions[*]' COLUMNS (username VARCHAR2(100) PATH '\$')) jp
     RIGHT JOIN dba_users u
     ON jp.username = u.username
     LEFT JOIN dba_stmt_audit_opts dsao
     ON u.username = COALESCE(dsao.user_name,u.username)
     AND dsao.audit_option = 'CREATE SESSION'
     CROSS JOIN noaudit_sessions ns
     WHERE ns.row_count > 0
     AND  jp.username IS NULL AND u.username IS NOT NULL AND dsao.user_name IS NULL
     AND  u.username NOT IN ('SYS') )
 LOOP
      DBMS_OUTPUT.put_line(p.audit_session_command);
      EXECUTE IMMEDIATE p.audit_session_command;
 END LOOP;

END;
/
EOSQL