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
    AND job_name = 'DELIUS_AUDIT_ARCHIVE';

  v_object_name dba_objects.object_name%TYPE;
  v_enabled dba_scheduler_jobs.enabled%TYPE;
  v_playbook_search VARCHAR2(50):='Audit Management';

BEGIN
   
  OPEN cur_check_pkg;
  FETCH cur_check_pkg INTO v_object_name;
  CLOSE cur_check_pkg;

  IF v_object_name = 'DELIUS_AUDIT_MANAGEMENT'
  THEN

    -- Check for the old archive sys-owned job and drop it
    OPEN cur_check_job ('SYS');
    FETCH cur_check_job INTO v_enabled;
    CLOSE cur_check_job;

    IF v_enabled IS NOT NULL
    THEN
      DBMS_SCHEDULER.drop_job('SYS.DELIUS_AUDIT_ARCHIVE');
    END IF;

    -- Check for the new AUDSYS archive job and create the job if needed
    OPEN cur_check_job ('AUDSYS');
    FETCH cur_check_job INTO v_enabled;
    CLOSE cur_check_job;

    IF v_enabled IS NULL
    THEN
      DBMS_SCHEDULER.CREATE_JOB (
              job_name => '"AUDSYS"."DELIUS_AUDIT_ARCHIVE"',
              job_type => 'PLSQL_BLOCK',
              job_action => 'BEGIN AUDSYS.delius_audit_management.archive_audit_trail; END;',
              number_of_arguments => 0,
              start_date => TRUNC(SYSDATE)+1,
              repeat_interval => 'FREQ=DAILY;BYDAY=MON,TUE,WED,THU,FRI,SAT,SUN;BYHOUR=23;BYMINUTE=00;BYSECOND=0',
              end_date => NULL,
              enabled => TRUE,
              auto_drop => FALSE,
              comments => 'Move Database Audit Records to the History Table');
      -- enable dbms_output to DBA_SCHEDULER_JOB_RUN_DETAILS
      DBMS_SCHEDULER.SET_ATTRIBUTE ( 
              name => '"AUDSYS"."DELIUS_AUDIT_ARCHIVE"',
              attribute => 'STORE_OUTPUT',
              value => TRUE);

      DBMS_OUTPUT.PUT_LINE(v_playbook_search||': Scheduled');
    ELSIF v_enabled = 'FALSE'
    THEN
      DBMS_SCHEDULER.enable(name => '"AUDSYS"."DELIUS_AUDIT_ARCHIVE"');
      DBMS_OUTPUT.PUT_LINE(v_playbook_search||': Enabled');
    ELSE
      DBMS_OUTPUT.PUT_LINE(v_playbook_search||' : Already Scheduled');
    END IF;    

  ELSE
    DBMS_OUTPUT.PUT_LINE(v_playbook_search||': No Audit Management Artefacts');
  END IF;

END;
/