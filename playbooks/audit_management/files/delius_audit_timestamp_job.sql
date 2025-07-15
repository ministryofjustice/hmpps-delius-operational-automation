WHENEVER SQLERROR EXIT FAILURE
SET SERVEROUTPUT ON SIZE UNLIMITED
SET VERIFY OFF 

DECLARE

  CURSOR cur_check_pkg IS
    SELECT object_name
    FROM dba_objects
    WHERE object_name = 'DELIUS_AUDIT_MANAGEMENT'
    AND owner = 'AUDSYS'
    AND object_type = 'PACKAGE BODY';

  CURSOR cur_check_job (p_owner varchar2) IS
    SELECT enabled 
    FROM dba_scheduler_jobs
    WHERE owner = p_owner
    AND job_name = 'SET_LAST_ARCHIVE_TIMESTAMP';

  v_object_name dba_objects.object_name%TYPE;
  v_enabled dba_scheduler_jobs.enabled%TYPE;
  v_playbook_search VARCHAR2(50):='Audit Management';

BEGIN
   
  OPEN cur_check_pkg;
  FETCH cur_check_pkg INTO v_object_name;
  CLOSE cur_check_pkg;

  IF v_object_name = 'DELIUS_AUDIT_MANAGEMENT'
  THEN

    -- check for the old sys-owned SET_LAST_ARCHIVE_TIMESTAMP job
    OPEN cur_check_job ('SYS');
    FETCH cur_check_job INTO v_enabled;
    CLOSE cur_check_job;

    IF v_enabled IS NOT NULL
    THEN
      -- Move it to the AUDSYS schema
      -- The dbms_audit_mgmt statements have been moved to the delius_audit_management package
      -- so update the job action to call the new procedure.
      DBMS_SCHEDULER.copy_job('SYS.SET_LAST_ARCHIVE_TIMESTAMP','AUDSYS.SET_LAST_ARCHIVE_TIMESTAMP');
      DBMS_SCHEDULER.set_attribute (
        name => '"AUDSYS"."SET_LAST_ARCHIVE_TIMESTAMP"',
        attribute => 'job_action',
        value => 'BEGIN AUDSYS.delius_audit_management.set_last_archive_timestamp; END;');
      DBMS_SCHEDULER.SET_ATTRIBUTE(
        name => '"AUDSYS"."SET_LAST_ARCHIVE_TIMESTAMP"',
        attribute => 'STORE_OUTPUT',
        value => TRUE);

      DBMS_SCHEDULER.drop_job(job_name => '"SYS"."SET_LAST_ARCHIVE_TIMESTAMP"');
    ELSE
    -- create the new audsys job if it doesn't exist
      OPEN cur_check_job ('AUDSYS');
      FETCH cur_check_job INTO v_enabled;
      CLOSE cur_check_job;

      IF v_enabled IS NULL
      THEN
          DBMS_SCHEDULER.CREATE_JOB (
            job_name => '"AUDSYS"."SET_LAST_ARCHIVE_TIMESTAMP"',
            job_type => 'PLSQL_BLOCK',
            job_action => 'BEGIN AUDSYS.delius_audit_management.set_last_archive_timestamp; END;',
            number_of_arguments => 0,
            start_date => TRUNC(SYSDATE)+1,
            repeat_interval => 'FREQ=DAILY; INTERVAL=1;',
            end_date => NULL,
            enabled => TRUE,
            auto_drop => FALSE,
            comments => 'SET_LAST_ARCHIVE_TIMESTAMP for Audit Trails');
          -- enable dbms_output to DBA_SCHEDULER_JOB_RUN_DETAILS
          DBMS_SCHEDULER.SET_ATTRIBUTE(
            name => '"AUDSYS"."SET_LAST_ARCHIVE_TIMESTAMP"',
            attribute => 'STORE_OUTPUT',
            value => TRUE);
          
      ELSE
        -- if the rentention period ever needs to be changed, update the job action here, e.g.
        --DBMS_SCHEDULER.set_attribute (
          --name => '"AUDSYS"."SET_LAST_ARCHIVE_TIMESTAMP"',
          --attribute => 'job_action',
          --value => 'BEGIN AUDSYS.delius_audit_management.set_last_archive_timestamp(p_day_cap => 31, p_unified_cap => 3); END;');
        NULL; -- do nothing for now and use the default retention periods
      END IF;
    END IF;

    DBMS_OUTPUT.PUT_LINE(v_playbook_search||': Enabled');
  ELSE
    DBMS_OUTPUT.PUT_LINE(v_playbook_search||': No Audit Management Artefacts');
  END IF;

END;
/