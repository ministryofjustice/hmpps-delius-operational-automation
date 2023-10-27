SET SERVEROUTPUT ON SIZE UNLIMITED

DECLARE

CURSOR c1 IS
  SELECT object_name
  FROM dba_objects
  WHERE object_name = 'DELIUS_AUDIT_MANAGEMENT'
  AND owner = 'SYS'
  AND object_type = 'PACKAGE BODY';

CURSOR c2 IS
  SELECT enabled 
  FROM dba_scheduler_jobs
  WHERE owner ='SYS'
  AND job_name = 'DELIUS_AUDIT_ARCHIVE';

v_object_name dba_objects.object_name%TYPE;
v_enabled dba_scheduler_jobs.enabled%TYPE;
v_playbook_search VARCHAR2(50):='Audit Management';

BEGIN
   
  OPEN c1;
  FETCH c1 INTO v_object_name;
  CLOSE c1;

  IF v_object_name = 'DELIUS_AUDIT_MANAGEMENT'
  THEN

    OPEN c2;
    FETCH c2 INTO v_enabled;
    CLOSE c2;

    IF v_enabled IS NULL
    THEN
      DBMS_SCHEDULER.CREATE_JOB (
              job_name => '"SYS"."DELIUS_AUDIT_ARCHIVE"',
              job_type => 'PLSQL_BLOCK',
              job_action => 'BEGIN delius_audit_management.archive_audit_trail; END;',
              number_of_arguments => 0,
              start_date => TO_TIMESTAMP_TZ('2019-11-04 23:00:00.000000000 EUROPE/LONDON','YYYY-MM-DD HH24:MI:SS.FF TZR'),
              repeat_interval => 'FREQ=DAILY;BYDAY=MON,TUE,WED,THU,FRI,SAT,SUN;BYHOUR=23;BYMINUTE=00;BYSECOND=0',
              end_date => NULL,
              enabled => TRUE,
              auto_drop => FALSE,
              comments => 'Move Database Audit Records to the History Table');
      DBMS_OUTPUT.PUT_LINE(v_playbook_search||': Scheduled');
    ELSIF v_enabled = 'FALSE'
    THEN  
      DBMS_SCHEDULER.enable(name => '"SYS"."DELIUS_AUDIT_ARCHIVE"');
      DBMS_OUTPUT.PUT_LINE(v_playbook_search||': Enabled');
    ELSE
      DBMS_OUTPUT.PUT_LINE(v_playbook_search||' :Already Scheduled');
    END IF;
  ELSE
    DBMS_OUTPUT.PUT_LINE(v_playbook_search||': No Audit Management Artefacts');
  END IF;

END;
/