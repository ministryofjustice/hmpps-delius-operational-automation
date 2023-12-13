#!/bin/bash
#
#  Create DELIUS_AUDIT_POOL.COMPRESS_AUDITED_INTERACTION job to periodically compress old AUDITED_INTERACTION partitions.
#  Old partitions should never be edited so are a candidate for BASIC compression which is available with Enterprise Edition.
#

. ~/.bash_profile

sqlplus /nolog <<EOSQL
connect / as sysdba


-- Remove previous version of the job if it exists
DECLARE
   l_existing_job INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO   l_existing_job
    FROM   dba_scheduler_jobs
    WHERE  owner = 'DELIUS_AUDIT_POOL'
    AND    job_name = 'COMPRESS_AUDITED_INTERACTION';
    
    IF l_existing_job > 0
    THEN
       DBMS_SCHEDULER.drop_job (
         job_name => 'DELIUS_AUDIT_POOL.COMPRESS_AUDITED_INTERACTION'
       );
       DBMS_SCHEDULER.drop_schedule (
         schedule_name => 'DELIUS_AUDIT_POOL.COMPRESSION_SCHEDULE'
       );       
       DBMS_SCHEDULER.drop_program (
         program_name => 'DELIUS_AUDIT_POOL.COMPRESS_AUDIT_PROG'
       ); 
    END IF;
END;
/

-- Enable required privileges for the DELIUS_AUDIT_POOL
-- to contain a job for compressing the AUDITED_INTERACTION TABLE

GRANT SELECT  ON dba_tab_partitions                    TO delius_audit_pool;
GRANT ALTER   ON delius_app_schema.audited_interaction TO delius_audit_pool;
GRANT ANALYZE ANY                                      TO delius_audit_pool;

DECLARE
   l_schedule_exists INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO   l_schedule_exists
    FROM   dba_scheduler_schedules
    WHERE  owner = 'DELIUS_AUDIT_POOL'
    AND    schedule_name = 'COMPRESSION_SCHEDULE';
    
    IF l_schedule_exists = 0
    THEN
        DBMS_SCHEDULER.CREATE_SCHEDULE (
            repeat_interval => 'FREQ=WEEKLY;BYDAY=SAT;BYHOUR=20',  
            start_date      => SYSTIMESTAMP,
            comments        => 'Run audit compression on Saturdays at 8pm.',
            schedule_name   => 'DELIUS_AUDIT_POOL.COMPRESSION_SCHEDULE');
    END IF;
END;
/


DECLARE
   l_program_exists INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO   l_program_exists
    FROM   dba_scheduler_programs
    WHERE  owner = 'DELIUS_AUDIT_POOL'
    AND    program_name = 'COMPRESSION_SCHEDULE';
    
    IF l_program_exists = 0
    THEN
        DBMS_SCHEDULER.create_program(
            program_name => 'DELIUS_AUDIT_POOL.COMPRESS_AUDIT_PROG',
            program_action => q'[
                DECLARE
                   l_oldest_uncomp_partition VARCHAR2(30);
                BEGIN
                
                        SELECT partition_name
                        INTO   l_oldest_uncomp_partition
                        FROM   dba_tab_partitions
                        WHERE  table_name = 'AUDITED_INTERACTION'
                        AND    partition_position = (
                                   SELECT    partition_position
                                   FROM      dba_tab_partitions
                                   WHERE     table_name = 'AUDITED_INTERACTION'
                                   AND       compression = 'DISABLED'
                                   INTERSECT
                                   SELECT    partition_position
                                   FROM      dba_tab_partitions
                                   WHERE     table_name = 'AUDITED_INTERACTION'
                                   AND       partition_position NOT IN (
                                                  SELECT   partition_position
                                                  FROM     dba_tab_partitions
                                                  WHERE    table_name = 'AUDITED_INTERACTION'
                                                  ORDER BY partition_position DESC
                                                  FETCH FIRST 3 ROWS ONLY)    -- Do not compress newest 3 partitions as these may be subject to insertion
                                   ORDER BY  partition_position
                                   FETCH FIRST ROW ONLY
                            );
                
                    DBMS_OUTPUT.put_line('Compressing AUDITED_INTERACTION partition '||l_oldest_uncomp_partition);
                    
                    -- Apply BASIC compression only as this is included with Enterprise Edition
                    EXECUTE IMMEDIATE 'ALTER TABLE delius_app_schema.audited_interaction MOVE PARTITION '
                                      ||l_oldest_uncomp_partition||' COMPRESS';
                
                    -- Update statistics for the newly compressed partition
                    DBMS_STATS.gather_table_stats(ownname  => 'DELIUS_APP_POOL'
                                                 ,tabname  => 'AUDITED_INTERACTION'
                                                 ,partname => l_oldest_uncomp_partition);
                EXCEPTION
                    -- No error if nothing to compress
                    WHEN no_data_found
                    THEN 
                       DBMS_OUTPUT.put_line('No data ready to compress.');
                END;
                    ]',
            program_type => 'PLSQL_BLOCK',
            number_of_arguments => 0,
            comments => 'Compress old partitions in AUDITED_INTERACTION',
            enabled => FALSE);
        DBMS_SCHEDULER.ENABLE(name=>'DELIUS_AUDIT_POOL.COMPRESS_AUDIT_PROG');   
   END IF;
END;
/

BEGIN
    DBMS_SCHEDULER.CREATE_JOB (
            job_name => 'DELIUS_AUDIT_POOL.COMPRESS_AUDITED_INTERACTION',
            program_name => 'DELIUS_AUDIT_POOL.COMPRESS_AUDIT_PROG',
            schedule_name => 'DELIUS_AUDIT_POOL.COMPRESSION_SCHEDULE',
            enabled => TRUE,
            comments => 'Apply BASIC compression of old partitions of AUDITED_INTERACTION each month.',     
            job_style => 'REGULAR');
END;
/

EXIT
EOSQL