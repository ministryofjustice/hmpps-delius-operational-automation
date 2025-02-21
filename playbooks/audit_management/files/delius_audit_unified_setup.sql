WHENEVER SQLERROR EXIT FAILURE
SET SERVEROUTPUT ON SIZE UNLIMITED
SET VERIFY OFF 

DECLARE

  CURSOR cur_check_aud_tablespace(p_tablespace_name VARCHAR2) IS
    SELECT 1
    FROM dba_tablespaces
    WHERE tablespace_name = p_tablespace_name;

  -- Using T_ORACLE_AUDIT_HISTORY as it's already larger than T_ORACLE_AUDIT
  v_tablespace_name VARCHAR2(30) := 'T_ORACLE_AUDIT_HISTORY';
  v_exists NUMBER;
  v_interval_number NUMBER := 1;
  v_interval_frequency VARCHAR2(10) := 'DAY';
  v_playbook_search VARCHAR2(50):='Audit Management';

BEGIN
   
  OPEN cur_check_aud_tablespace(v_tablespace_name);
  FETCH cur_check_aud_tablespace INTO v_exists;
  CLOSE cur_check_aud_tablespace;
  -- only move the audit trail if the tablespace exists
  IF v_exists IS NOT NULL THEN
    -- set the tablespace for the unified audit trail to T_ORACLE_AUDIT_HISTORY so partitions can be compressed
    DBMS_AUDIT_MGMT.SET_AUDIT_TRAIL_LOCATION(
      AUDIT_TRAIL_TYPE => DBMS_AUDIT_MGMT.audit_trail_unified,
      AUDIT_TRAIL_LOCATION_VALUE => v_tablespace_name);

    -- set the default compression for the tablespace as it can't set at the table level for the unified audit trail (no ddl allowed on it)
    EXECUTE IMMEDIATE 'ALTER TABLESPACE '||v_tablespace_name||' DEFAULT COMPRESS BASIC';
  END IF;
  -- set the partition interval to 1 day which will improve performance when purging as partitions will be dropped
  -- instead of running DELETE statements.
  DBMS_AUDIT_MGMT.ALTER_PARTITION_INTERVAL(
    interval_number       => v_interval_number,
    interval_frequency    => v_interval_frequency);

  DBMS_AUDIT_MGMT.SET_AUDIT_TRAIL_PROPERTY(
    audit_trail_type            => DBMS_AUDIT_MGMT.AUDIT_TRAIL_UNIFIED,
    audit_trail_property        => DBMS_AUDIT_MGMT.AUDIT_TRAIL_WRITE_MODE,
    audit_trail_property_value  => DBMS_AUDIT_MGMT.AUDIT_TRAIL_IMMEDIATE_WRITE);

  DBMS_OUTPUT.PUT_LINE(v_playbook_search||': Enabled');

END;
/