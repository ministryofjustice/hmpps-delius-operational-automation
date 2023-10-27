#!/bin/bash

. ~/.bash_profile

# Define the number of days after which a SQL is deemed to have aged.
# (i.e. sufficient time has passed since it was previously parsed
#  to make it worth while re-parsing to take account of volume changes)
export AGE_LIMIT_DAYS=1

sqlplus -s /  as sysdba <<EOF
SET LINES 1000
SET PAGES 0
WHENEVER SQLERROR EXIT FAILURE

GRANT EXECUTE ON dbms_shared_pool TO delius_user_support;

GRANT SELECT ON sys.v_\$sql TO delius_user_support;

GRANT SELECT ON sys.v_\$sql_plan TO delius_user_support;

SET SERVEROUT ON

DECLARE
    l_owner        CONSTANT VARCHAR2(30) := 'DELIUS_USER_SUPPORT';
    l_program_name CONSTANT VARCHAR2(30) := 'PURGE_DYNAMIC_SAMPLE_SQL';
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
FOR aged_dynamic_sql IN (
    WITH aged_sql
    AS (
        SELECT DISTINCT s.sql_id
                       ,s.address
                       ,s.hash_value
        FROM   v\$sql s
        WHERE  s.parsing_schema_name = 'DELIUS_APP_SCHEMA'
        AND    s.sql_text NOT LIKE '/* MV_REFRESH (MRG) */%'   -- Ignore materialized view refreshes
        AND    SYSDATE - TO_DATE(s.last_load_time,'YYYY-MM-DD/HH24:MI:SS') > ${AGE_LIMIT_DAYS}   -- Include cached SQL first loaded over defined number of days ago 
    ), 
    dynamic_sql 
    AS (
        SELECT DISTINCT sp.sql_id
        FROM   v\$sql_plan sp
        WHERE  sp.other_xml IS NOT NULL
        AND    XMLEXISTS('\$OTHER//other_xml/info[@type="dynamic_sampling"]' PASSING XMLTYPE(sp.other_xml) AS "OTHER")
    )
    SELECT     a.address||','||a.hash_value cursor_name
              ,a.sql_id
              ,ROW_NUMBER() OVER (ORDER BY a.sql_id) row_number
              ,COUNT(*) OVER () number_of_sqls_to_purge
    FROM       aged_sql a
    INNER JOIN dynamic_sql d
    ON         a.sql_id = d.sql_id
    ORDER BY   a.sql_id)
LOOP
   IF aged_dynamic_sql.row_number = 1 THEN
      DBMS_OUTPUT.put('purged('||aged_dynamic_sql.number_of_sqls_to_purge||'):');
   ELSE
      DBMS_OUTPUT.put(',');
   END IF;
   sys.DBMS_SHARED_POOL.purge(name=>aged_dynamic_sql.cursor_name,flag=>'C');
   DBMS_OUTPUT.put(aged_dynamic_sql.sql_id);
END LOOP;
DBMS_OUTPUT.new_line;
END;
}'
    ,enabled         =>  TRUE
    ,comments        =>  'See '||l_job_name||' comments.');

   DBMS_SCHEDULER.create_job(
        job_name        =>  l_owner || '.' || l_job_name 
       ,program_name    =>  l_owner || '.' || l_program_name 
       ,schedule_name   =>  'SYS.MAINTENANCE_WINDOW_GROUP'
       ,comments        =>  'When new tables do not have optimizer statistics gathered, any SQL against these tables will be '||
                            'optimized using dynamic sampling.   Since these are new tables, the data shape will be volatile. '||
                            'Therefore we do not wish to use SQL based on dynamically sampled values for a long period of '||
                            'time before re-sampling.   Therefore we periodically detect and purge these SQLs.' 
       ,enabled         =>  TRUE);

END;
/

EXIT
EOF
