#!/bin/bash

. ~/.bash_profile

sqlplus -s /  as sysdba <<EOF
SET LINES 1000
SET PAGES 0
WHENEVER SQLERROR EXIT FAILURE

GRANT SELECT ON sys.v_\$sort_usage TO delius_user_support;
GRANT SELECT ON sys.v_\$parameter TO delius_user_support;
GRANT SELECT ON sys.v_\$session TO delius_user_support;

SET SERVEROUT ON

DECLARE
    l_owner        CONSTANT VARCHAR2(30) := 'DELIUS_USER_SUPPORT';
    l_program_name CONSTANT VARCHAR2(30) := 'TEMP_SPACE_MANAGEMENT';
    l_job_name     CONSTANT VARCHAR2(30) := l_program_name || '_JOB';
BEGIN

  FOR x IN (SELECT job_name
            FROM   dba_scheduler_jobs
            WHERE  owner = l_owner
            AND    job_name  = l_job_name )
  LOOP
     DBMS_SCHEDULER.drop_job(
       job_name         =>  l_owner || '.' || l_job_name
     );
  END LOOP;

  FOR x IN (SELECT program_name
            FROM   dba_scheduler_programs
            WHERE  owner = l_owner
            AND    program_name  = l_program_name )
  LOOP
     DBMS_SCHEDULER.drop_program(
       program_name     =>  l_owner || '.' || l_program_name
     );
  END LOOP;

  DBMS_SCHEDULER.create_program (
     program_name    =>  l_owner || '.' || l_program_name 
    ,program_type    =>  'PLSQL_BLOCK'
    ,program_action  =>  q'{
BEGIN
FOR session_using_excess_temp IN (
      SELECT
         sid,
         serial#,
         sql_id_tempseg,
         temp_space_gb
      FROM
         (
            SELECT
                  se.sid,
                  se.serial#,
                  sql_id_tempseg,
                  blocks * (
                     SELECT
                        value
                     FROM
                        v\$parameter
                     WHERE
                        name = 'db_block_size'
                  ) / 1024 / 1024 / 1024 temp_space_gb
            FROM
                     v\$sort_usage su
                  INNER JOIN v\$session se ON su.session_addr = se.saddr
                                             AND se.program = 'WIReportServer.exe'
         )
      WHERE
         temp_space_gb > ${MAX_TEMP_SPACE_GB}
)
LOOP
   DBMS_OUTPUT.put('Session '||session_using_excess_temp.sid||','||session_using_excess_temp.serial#||
                   ' running SQL_ID '||session_using_excess_temp.sql_id_tempseg||
                   ' is using '||ROUND(session_using_excess_temp.temp_space_gb,1)||' Gb of temp space. ');
   DBMS_OUTPUT.put_line('This exceeds ${MAX_TEMP_SPACE_GB} Gb limit. Session will be killed. ');
   EXECUTE IMMEDIATE 'ALTER SYSTEM KILL SESSION '''||
                      session_using_excess_temp.sid||','||session_using_excess_temp.serial#||
                      ''' IMMEDIATE';
END LOOP;
END;
}'
    ,enabled         =>  TRUE
    ,comments        =>  'See '||l_job_name||' comments.');

   DBMS_SCHEDULER.create_job(
        job_name        =>  l_owner || '.' || l_job_name 
       ,program_name    =>  l_owner || '.' || l_program_name 
       ,repeat_interval =>  'FREQ=MINUTELY;INTERVAL=${CHECK_INTERVAL_MINUTES}'
       ,comments        =>  'Periodically check for WIReport.exe sessions using more than ${MAX_TEMP_SPACE_GB} Gb of temp space and kill those.' 
       ,enabled         =>  TRUE);

END;
/

EXIT
EOF
