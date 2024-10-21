#!/bin/bash

. ~/.bash_profile

sqlplus -s /  as sysdba <<EOF
SET LINES 1000
SET PAGES 0
WHENEVER SQLERROR EXIT FAILURE

GRANT EXECUTE ON dbms_shared_pool TO delius_user_support;

GRANT SELECT ON sys.v_\$sqlarea TO delius_user_support;

GRANT SELECT ON sys.v_\$sql_shared_cursor TO delius_user_support;

SET SERVEROUT ON

DECLARE
    l_owner        CONSTANT VARCHAR2(128) := 'DELIUS_USER_SUPPORT';
    l_program_name CONSTANT VARCHAR2(128) := 'MV_REFRESH_PURGE_CHILD_CURSORS';
    l_job_name     CONSTANT VARCHAR2(128) := l_program_name || '_JOB';
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
DECLARE
    l_count        INTEGER := 0;
    l_sharable_mem INTEGER := 0;
BEGIN
/*
       We identify cursors to purge by the following criteria:
       1. They contain an MV_REFRESH comment or a DELETE from a MV, and
       2. They are not sharable due to the use of Flashback, and
       3. They have a child version count above 5
    */
    FOR x IN (
        SELECT
            sql_id,
            address,
            hash_value,
            sharable_mem,
            version_count
        FROM
            v\$sqlarea s
        WHERE
            (UPPER(s.sql_text) LIKE '/* MV_REFRESH (MRG) */%'
            OR UPPER(s.sql_text) LIKE 'DELETE%MV" SNAP$%')
            AND s.version_count > 5
            AND EXISTS (
                SELECT
                    1
                FROM
                    v\$sql_shared_cursor c
                WHERE
                        c.sql_id = s.sql_id
                    AND c.flashback_cursor = 'Y'
            )
    ) LOOP
        sys.DBMS_SHARED_POOL.purge(x.address|| ','|| x.hash_value, 'C');

        l_count := l_count + x.version_count;
        l_sharable_mem := l_sharable_mem + x.sharable_mem;
    END LOOP;

    DBMS_OUTPUT.put_line('Purged '
                         || l_count
                         || ' unsharable cursors and released '
                         || round(l_sharable_mem / 1024 / 1024, 2)
                         || 'Mb of memory.');

END;
}'
    ,enabled         =>  TRUE
    ,comments        =>  'See '||l_job_name||' comments.');

   DBMS_SCHEDULER.create_job(
        job_name        =>  l_owner || '.' || l_job_name 
       ,program_name    =>  l_owner || '.' || l_program_name
       ,start_date      =>  SYSTIMESTAMP
       ,repeat_interval =>  'FREQ=HOURLY;'
       ,end_date        =>  NULL
       ,comments        =>  'Materialized View refresh cursors are not sharable as they use flashback query. '||
                            'This means that regular MV refreshes will gradually consume a large amount of '||
                            'shared pool memory but will never be reused.  This job detects such cursors and '||
                            'purges them to ensure this memory may be reallocated to other components.' 
       ,enabled         =>  TRUE);

END;
/

EXIT
EOF
