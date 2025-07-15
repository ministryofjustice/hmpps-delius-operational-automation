WHENEVER SQLERROR EXIT FAILURE
SET SERVEROUTPUT ON SIZE UNLIMITED
SET VERIFY OFF 

DECLARE

  l_obj_exists NUMBER(3);
  l_owner     VARCHAR2(30) := 'SYS';
  l_obj_name  VARCHAR2(30) := 'DELIUS_AUDIT_MANAGEMENT';

BEGIN

  -- Drop the package if it exists as it will be moved into the AUDSYS schema
  SELECT COUNT(*)
  INTO   l_obj_exists
  FROM   dba_objects
  WHERE  object_name = l_obj_name
  AND    owner = l_owner
  AND    object_type = 'PACKAGE';

  IF l_obj_exists = 1 THEN
    EXECUTE IMMEDIATE 'DROP PACKAGE '||l_owner||'.'||l_obj_name;
  END IF;

END;
/

DECLARE

  l_obj_exists NUMBER(3);
  l_owner     VARCHAR2(30) := 'SYS';
  l_obj_name  VARCHAR2(30) := 'HIST_AUD$';

BEGIN

  -- HIST_AUD$ won't exist in some databases e.g. MIS
  SELECT COUNT(*)
  INTO   l_obj_exists
  FROM   dba_objects
  WHERE  object_name = l_obj_name
  AND    owner = l_owner
  AND    object_type = 'TABLE';

  IF l_obj_exists = 1 THEN
    EXECUTE IMMEDIATE 'GRANT INSERT ON '||l_owner||'.'||l_obj_name||' TO AUDSYS';
  END IF;

END;
/

CREATE OR REPLACE PROCEDURE sys.drop_hist_aud_partition(p_partition_name VARCHAR2) AS
-- Drop a partition from the sys.hist_aud$ table. Used by jobs run by AUDSYS
BEGIN
  EXECUTE IMMEDIATE 'ALTER TABLE sys.hist_aud$ DROP PARTITION ' || p_partition_name;
END;
/

GRANT EXECUTE ON sys.drop_hist_aud_partition TO audsys;
GRANT SELECT, DELETE ON SYS.AUD$ TO AUDSYS;

CREATE OR REPLACE PACKAGE AUDSYS.delius_audit_management
AS
  -- Archive audit records to history table
  -- Apply a cap on the number of days data to be archived at once to prevent overloading
  --
  -- This package should be installed into the AUDSYS schema. 
  -- Requires invoker’s rights so it is executed with the privileges of the calling user e.g. SYS runs the scheduler jobs.
  --
  PROCEDURE archive_audit_trail (p_day_cap INTEGER DEFAULT 2);

  -- Procedure called from dbms_scheduler job AUDSYS.SET_LAST_ARCHIVE_TIMESTAMP
  -- This effectively marks all audit records up to n days ago as archived.
  -- The job was calling the statements directly but these have now been moved to this procedure.
  PROCEDURE set_last_archive_timestamp (
    p_day_cap IN INTEGER DEFAULT 31,
    p_unified_cap IN INTEGER DEFAULT 13 -- months
    );

END delius_audit_management;
/


CREATE OR REPLACE PACKAGE BODY AUDSYS.delius_audit_management
AS
-- Archive audit records to history table
-- Apply a cap on the number of days data to be archived at once to prevent overloading
PROCEDURE     archive_audit_trail (p_day_cap IN INTEGER DEFAULT 2)
AS
  CURSOR cur_uni_last_ts IS
    SELECT last_archive_ts
    FROM dba_audit_mgmt_last_arch_ts
    INNER JOIN v$database 
    ON v$database.dbid = dba_audit_mgmt_last_arch_ts.database_id
    WHERE  audit_trail = 'UNIFIED AUDIT TRAIL'
    AND    container_guid = (SELECT guid
                              FROM   v$containers
                              WHERE  con_id=0);
  --
  CURSOR cur_check_aud IS
    SELECT 1
    FROM sys.aud$
    WHERE ROWNUM = 1;
  --
  CURSOR cur_check_hist_aud IS
    SELECT 1
    FROM dba_objects
    WHERE object_name = 'HIST_AUD$'
    AND owner = 'SYS';
  --
  CURSOR cur_check_aud_tablespace IS
    SELECT 1
    FROM dba_tablespaces
    WHERE tablespace_name = 'T_ORACLE_AUDIT';
  --
  l_archive_date    TIMESTAMP;
  l_batch_counter   INTEGER := 0;
  l_record_chk  INTEGER := 0;
  l_capped_date     sys.aud$.ntimestamp#%TYPE;
  l_audit_option    VARCHAR2(10);
  l_hist_aud_found  INTEGER;
  l_tablespace      VARCHAR2(50);
  l_output          VARCHAR2(4000);
  --
BEGIN

  SELECT value
  INTO l_audit_option
  FROM v$option
  WHERE parameter = 'Unified Auditing';

  --
  -- UNIFIED AUDITING
  --
  IF l_audit_option = 'TRUE' THEN
    -- The DBA_AUDIT_MGMT_LAST_ARCH_TS view will be empty immediately after an
    -- environment refresh; default it to a sensible value which is chosen
    -- as 13 months per the Security Guidance.
    OPEN cur_uni_last_ts;
    FETCH cur_uni_last_ts INTO l_archive_date;
    CLOSE cur_uni_last_ts;
    IF l_archive_date IS NULL THEN
      l_archive_date := ADD_MONTHS(SYSDATE,-13);
      -- Update last_archive_ts_parameter with latest archival date
      DBMS_AUDIT_MGMT.set_last_archive_timestamp(
        audit_trail_type  => DBMS_AUDIT_MGMT.audit_trail_unified,
        last_archive_time => l_archive_date
        );      
    END IF;

    -- Direct DML can't be used on the unified audit trail so we use the built-in cleanup procedure.
    DBMS_AUDIT_MGMT.CLEAN_AUDIT_TRAIL(
      audit_trail_type => DBMS_AUDIT_MGMT.audit_trail_unified_table,
      use_last_arch_timestamp => TRUE
      );
    -- Check output in DBA_SCHEDULER_JOB_RUN_DETAILS
    l_output := 'Unified recs archived to '||TO_CHAR(l_archive_date,'DD Mon YYYY')||'.';
  END IF;

  -- TRADITIONAL AUDITING
  -- After migrating to unified audit, the following will still need to be done until sys.aud$ no longer holds any records
  --
  OPEN cur_check_aud;
  FETCH cur_check_aud INTO l_record_chk;
  CLOSE cur_check_aud;

  -- Skip if there are no records in the old audit trail
  IF l_record_chk = 1
  THEN
    l_output := l_output || 'Found records in legacy sys.aud$ table.';
    -- We use the built-in audit trail cleanup pointer to track the timestamp for the audit trail to
    -- be archived, although the built-in purge job is not used.
    IF NOT DBMS_AUDIT_MGMT.IS_CLEANUP_INITIALIZED(DBMS_AUDIT_MGMT.audit_trail_aud_std)
    THEN
      OPEN cur_check_aud_tablespace;
      FETCH cur_check_aud_tablespace INTO l_tablespace;
      CLOSE cur_check_aud_tablespace;
      -- only move the audit trail if the tablespace exists
      IF l_tablespace IS NOT NULL THEN
        DBMS_AUDIT_MGMT.SET_AUDIT_TRAIL_LOCATION(
            audit_trail_type  => DBMS_AUDIT_MGMT.audit_trail_aud_std,
            audit_trail_location_value => 'T_ORACLE_AUDIT') ;
      END IF;          
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
    -- Note that a separate schedule job which calls the procedure set_last_archive_timestamp 
    -- in this package advances the last_archive_ts parameter.
    --
    -- The DBA_AUDIT_MGMT_LAST_ARCH_TS view will be empty immediately after an
    -- environment refresh; default it to a sensible value which is chosen
    -- as 1 day prior to the 2 week lag limit.   This will be refined based
    -- on applying the data cap if necessary in subsequent logic.
    SELECT COALESCE(TRUNC(MIN(last_archive_ts)) , SYSDATE-15 )
    INTO   l_archive_date
    FROM   dba_audit_mgmt_last_arch_ts
    INNER JOIN v$database 
    ON v$database.dbid = dba_audit_mgmt_last_arch_ts.database_id
    WHERE  audit_trail = 'STANDARD AUDIT TRAIL'
    AND    container_guid = (SELECT guid
                              FROM   v$containers
                              WHERE  con_id=0);

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

    -- Check if the db has the hist_aud$ table in it
    OPEN cur_check_hist_aud;
    FETCH cur_check_hist_aud INTO l_hist_aud_found;
    CLOSE cur_check_hist_aud;

    IF l_hist_aud_found IS NOT NULL THEN
      -- Ensure we do not use parallelism to move the data as this is a background task
      -- which should run with minimal impact on other users.
      EXECUTE IMMEDIATE 'INSERT /*+ APPEND NOPARALLEL */ INTO sys.hist_aud$
      SELECT * FROM sys.aud$
      WHERE  ntimestamp# <= :archive_date' using l_archive_date;
    END IF;
    
    -- Delete the old records from the audit table irrespective of whether the hist table exists
    DELETE /*+ NOPARALLEL */ FROM sys.aud$
    WHERE  ntimestamp# <= l_archive_date;

    -- From 18c we can now include output in the scheduler job logs using DBMS_OUTPUT
    -- Check output in DBA_SCHEDULER_JOB_RUN_DETAILS
    l_output := l_output || 'Archived '||SQL%ROWCOUNT||' rows from sys.aud$ to '||TO_CHAR(l_archive_date,'DD Mon YYYY')||'.';

    COMMIT;

    -- Update last_archive_ts_parameter with latest archival date
    DBMS_AUDIT_MGMT.set_last_archive_timestamp(
      audit_trail_type  => DBMS_AUDIT_MGMT.audit_trail_aud_std,
      last_archive_time => l_archive_date
      );
    --
  END IF;

  -- If the db has the hist table, drop partitions from the old hist table older than 13 months per security guidance
  DECLARE
    -- It's quicker to drop partitions by name so use the high_value to check what partitions are present
    CURSOR cur_partitions IS
        WITH date_partition AS (
            SELECT  partition_name,
                   TO_DATE(
                        substr(
                            extractvalue(dbms_xmlgen.getxmltype(
                                'select high_value FROM ALL_TAB_PARTITIONS WHERE table_name = ''' || t.table_name || ''' and PARTITION_NAME = ''' || t.partition_name || ''''
                            ), '//text()')
                        , 11, 11)
                    ,'YYYY-MM-DD') 
                    AS high_value_t
            FROM all_tab_partitions t
            WHERE TABLE_NAME = 'HIST_AUD$'
        ) 
        SELECT partition_name, high_value_t-1 as high_value
        FROM date_partition
        WHERE high_value_t < ADD_MONTHS(TRUNC(SYSDATE),-13)
        ORDER BY high_value;
    l_partition_count INTEGER;
    l_date_string VARCHAR2(10);
    l_sql varchar2(200);
  BEGIN
    -- Check if the table exists and is partitioned
    SELECT COUNT(*) 
    INTO l_partition_count
    FROM ALL_TAB_PARTITIONS
    WHERE TABLE_NAME = 'HIST_AUD$' AND TABLE_OWNER = 'SYS';

    -- If the table is not partitioned or only has 1 partition left, don't try to run the partition maintenance.
    -- NB you can't drop the last partition left in the table.
    IF l_partition_count > 1 THEN
      FOR r_partitions IN cur_partitions LOOP
        l_output := SUBSTR(l_output || 'Dropping partition '||r_partitions.partition_name||' from legacy sys.hist_aud$ table.', 1, 4000);
        sys.drop_hist_aud_partition(r_partitions.partition_name);
      END LOOP;
    ELSIF l_partition_count = 1 THEN
      -- Continue to delete data from the last partition
      EXECUTE IMMEDIATE 'DELETE /*+ NOPARALLEL */ FROM sys.hist_aud$
      WHERE  ntimestamp# <= ADD_MONTHS(TRUNC(SYSDATE),-13)';
    END IF;
  END;

  DBMS_OUTPUT.put_line(l_output);

END archive_audit_trail;

-- Procedure called from dbms_scheduler job AUDSYS.SET_LAST_ARCHIVE_TIMESTAMP
-- This effectively marks all audit records up to n days ago as archived.
-- The job was calling the statements directly but these have now been moved to this procedure.
PROCEDURE set_last_archive_timestamp (
    p_day_cap IN INTEGER DEFAULT 31,
    p_unified_cap IN INTEGER DEFAULT 13 -- months
    )
AS
BEGIN
  IF DBMS_AUDIT_MGMT.IS_CLEANUP_INITIALIZED(DBMS_AUDIT_MGMT.audit_trail_aud_std)
  THEN
    -- set the last archive timestamp to n days ago for Standard Audit Trail and FGA Audit Trails
    DBMS_AUDIT_MGMT.set_last_archive_timestamp(
      audit_trail_type => DBMS_AUDIT_MGMT.audit_trail_aud_std, 
      last_archive_time => SYSTIMESTAMP-p_day_cap
      );
  END IF;
  IF DBMS_AUDIT_MGMT.IS_CLEANUP_INITIALIZED(DBMS_AUDIT_MGMT.audit_trail_fga_std)
  THEN
    DBMS_AUDIT_MGMT.set_last_archive_timestamp(
      audit_trail_type => DBMS_AUDIT_MGMT.audit_trail_fga_std, 
      last_archive_time => SYSTIMESTAMP-p_day_cap
      );
  END IF;
  
  -- Unified auditing changes:
  -- Set the last archive timestamp to 13 months ago for Unified Audit Trail per retentions rules in Security Guidance
  DBMS_AUDIT_MGMT.set_last_archive_timestamp(
    audit_trail_type => DBMS_AUDIT_MGMT.audit_trail_unified, 
    last_archive_time => ADD_MONTHS(SYSTIMESTAMP, p_unified_cap*-1)
    );

  -- Load the os unified audit files from the audit directory if any exist
  DBMS_AUDIT_MGMT.LOAD_UNIFIED_AUDIT_FILES;

END set_last_archive_timestamp;

END delius_audit_management;
/
show errors
