SET SERVEROUTPUT ON SIZE UNLIMITED
SET VERIFY OFF 

DECLARE

CURSOR c1 IS
  SELECT count(object_name) cnt 
  FROM dba_objects
  WHERE owner = 'DELIUS_CFO'
  AND object_name = 'CFO';  

CURSOR c2 IS
  SELECT  enabled
  FROM dba_scheduler_jobs
  WHERE owner ='DELIUS_CFO'
  AND job_name = 'DAILY_CFO_DIFFERENTIAL_EXTRACT';

v_object_count NUMBER(2);
v_enabled dba_scheduler_jobs.enabled%TYPE;
v_playbook_search VARCHAR2(50):='CFO Daily Differential Extract';

BEGIN

  OPEN c1; 
  FETCH c1 INTO v_object_count;
  CLOSE c1; 

    IF v_object_count = 2 
    THEN
      EXECUTE IMMEDIATE 'CREATE OR REPLACE DIRECTORY CFO_EXTERNAL_DATA AS '||''''||'&1'||'''';
      DBMS_OUTPUT.PUT_LINE('CFO Database Directory Created');

      OPEN c2;
      FETCH c2 INTO v_enabled;
      CLOSE c2;

        IF v_enabled IS NULL
        THEN
          DBMS_SCHEDULER.CREATE_JOB (
            job_name => '"DELIUS_CFO"."DAILY_CFO_DIFFERENTIAL_EXTRACT"',
            job_type => 'PLSQL_BLOCK',
            job_action => 'BEGIN CFO.generateExtract(extract_type_in => ''DIFF''); END;',
            number_of_arguments => 0,
            start_date => TO_TIMESTAMP_TZ('2019-11-19 00:15:00.000000000 EUROPE/LONDON','YYYY-MM-DD HH24:MI:SS.FF TZR'),
            repeat_interval => 'FREQ=DAILY;BYDAY=MON,TUE,WED,THU,FRI,SAT,SUN;BYHOUR=00;BYMINUTE=15;BYSECOND=0',
            end_date => NULL,
            enabled => TRUE,
            auto_drop => FALSE,
            comments => 'Create daily differential extract for CFO');
          DBMS_OUTPUT.PUT_LINE(v_playbook_search||': Scheduled');
        ELSIF v_enabled = 'FALSE'
        THEN
          DBMS_SCHEDULER.enable( name => '"DELIUS_CFO"."DAILY_CFO_DIFFERENTIAL_EXTRACT"');
          DBMS_OUTPUT.PUT_LINE(v_playbook_search||': Enabled');
        ELSE
          DBMS_OUTPUT.PUT_LINE(v_playbook_search||' :Already Scheduled');
        END IF;

    ELSE
      DBMS_OUTPUT.PUT_LINE(v_playbook_search||': No or Incorrect CFO Artefacts');
    END IF;
END;
/
