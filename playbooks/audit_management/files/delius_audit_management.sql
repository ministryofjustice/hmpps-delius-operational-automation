CREATE OR REPLACE PACKAGE delius_audit_management
AS
    -- Archive audit records to history table
    -- Apply a cap on the number of days data to be archived at once to prevent overloading
    --
    -- For now this package should be installed into the SYS schema. 
    -- This may change in future.
    --
    PROCEDURE archive_audit_trail (p_day_cap INTEGER DEFAULT 2);
END delius_audit_management;

/


CREATE OR REPLACE PACKAGE BODY delius_audit_management
AS

-- Archive audit records to history table
-- Apply a cap on the number of days data to be archived at once to prevent overloading
PROCEDURE     archive_audit_trail (p_day_cap IN INTEGER DEFAULT 2)
AS
  --
  l_archive_date    TIMESTAMP;
  l_batch_counter   INTEGER := 0;
  l_record_counter  INTEGER := 0;
  l_capped_date     sys.aud$.ntimestamp#%TYPE;
  --
BEGIN

  --
  -- We use the built-in audit trail cleanup pointer to track the timestamp for the audit trail to
  -- be archived, although the built-in purge job is not used.
  IF NOT DBMS_AUDIT_MGMT.IS_CLEANUP_INITIALIZED(DBMS_AUDIT_MGMT.audit_trail_aud_std)
  THEN
     DBMS_AUDIT_MGMT.SET_AUDIT_TRAIL_LOCATION(
        audit_trail_type  => DBMS_AUDIT_MGMT.audit_trail_aud_std,
        audit_trail_location_value => 'T_ORACLE_AUDIT') ;
        
     DBMS_AUDIT_MGMT.init_cleanup(
        audit_trail_type => DBMS_AUDIT_MGMT.audit_trail_aud_std,
        default_cleanup_interval => 6 /* hours (value is required but not used as we do not set up purge job) */);
        
     -- Initialize cleanup pointer at start of audit trail
     SELECT TRUNC(NVL(MIN(ntimestamp#),SYSTIMESTAMP))
     INTO   l_archive_date
     FROM   sys.aud$;
     
     DBMS_AUDIT_MGMT.set_last_archive_timestamp(
        audit_trail_type  => DBMS_AUDIT_MGMT.audit_trail_aud_std,
        last_archive_time => l_archive_date
     );
  END IF;

  --
  -- Note that a separate schedule job advances the last_archive_ts parameter 
  --
  -- The DBA_AUDIT_MGMT_LAST_ARCH_TS view will be empty immediately after an
  -- environment refresh; default it to a sensible value which is chosen
  -- as 1 day prior to the 2 week lag limit.   This will be refined based
  -- on applying the data cap if necessary in subsequent logic.
  $IF dbms_db_version.ver_le_11
   $THEN
        SELECT TRUNC(last_archive_ts) 
        INTO   l_archive_date
        FROM   dba_audit_mgmt_last_arch_ts
        WHERE  audit_trail = 'STANDARD AUDIT TRAIL';
   $ELSE
        SELECT COALESCE(TRUNC(MIN(last_archive_ts)) , SYSDATE-15 )
        INTO   l_archive_date
        FROM   dba_audit_mgmt_last_arch_ts
        INNER JOIN v$database 
        ON v$database.dbid = dba_audit_mgmt_last_arch_ts.database_id
        WHERE  audit_trail = 'STANDARD AUDIT TRAIL'
        AND    container_guid = (SELECT guid
                                 FROM   v$containers
                                 WHERE  con_id=0);
   $END

  --
  -- Catch-all if the last_archive_ts_parameter has not been advanced;
  -- do not let the archival date lag the current date by more than 2 weeks
  IF l_archive_date <= TRUNC(SYSDATE - 14) THEN
    l_archive_date := TRUNC(SYSDATE - 14);
  END IF;

  --
  -- If the number of days we are about to archive exceeds the cap of p_days
  -- then we limit it further to reduce the load on the server and redo generation
  -- We do need need to scan the entire table to find this out - a random
  -- sample will get close enough as it is an unindexed column and would
  -- otherwise take excessively long to determine exactly.
  SELECT TRUNC(MIN(ntimestamp#)+2) capped_date
  INTO   l_capped_date
  FROM   sys.aud$
  SAMPLE (0.001);

  IF l_archive_date > l_capped_date THEN
     l_archive_date := l_capped_date;
  END IF;

  -- Ensure we do not use parallelism to move the data as this is a background task
  -- which should run with minimal impact on other users.

  INSERT /*+ APPEND NOPARALLEL */ INTO sys.hist_aud$
  SELECT *
  FROM   sys.aud$
  WHERE  ntimestamp# <= l_archive_date;
  
  DELETE /*+ NOPARALLEL */ FROM sys.aud$
  WHERE  ntimestamp# <= l_archive_date;

  -- From 18c we can now include output in the scheduler job logs using DBMS_OUTPUT 
  DBMS_OUTPUT.put_line(SQL%ROWCOUNT||' rows archived to '||TO_CHAR(l_archive_date,'DD Mon YYYY')||'.');

  COMMIT;

  -- Update last_archive_ts_parameter with latest archival date
  DBMS_AUDIT_MGMT.set_last_archive_timestamp(
     audit_trail_type  => DBMS_AUDIT_MGMT.audit_trail_aud_std,
     last_archive_time => l_archive_date
     );
  --
END archive_audit_trail;

END delius_audit_management;
/
