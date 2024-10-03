#!/bin/bash 
 
 . ~/.bash_profile

DFI_SCHEMAS="'DFIMIS_LANDING','DFIMIS_SUBSCRIBER','DFIMIS_DATA','DFIMIS_WORKING','DFIMIS_LOADER','DFIMIS_ABC'"
DFI_SCHEMAS_NO=$(echo ${DFI_SCHEMAS} | sed 's/,/ /g;s/'\''//g' | wc -w | xargs)
ACTION=${1}

sqlplus -s / as sysdba << EOF
SET SERVEROUTPUT ON
SET ECHO OFF
SET FEED OFF
SET LINES 132
DECLARE

lc_count          NUMBER;
lc_dp_handle      NUMBER;
lc_dump_name      VARCHAR2(100):='DFISCHEMAS';
lc_job_state      VARCHAR2(100);
lc_job_mode       VARCHAR2(100):=UPPER('${ACTION}');
lc_job_name       VARCHAR2(100):=lc_job_mode||lc_dump_name;
lc_dump_type      VARCHAR2(100):=DBMS_DATAPUMP.KU\$_FILE_TYPE_DUMP_FILE;
lc_log_type       VARCHAR2(100):=DBMS_DATAPUMP.KU\$_FILE_TYPE_LOG_FILE;

BEGIN

  SELECT COUNT(*)
  INTO lc_count
  FROM dba_users
  WHERE username IN (${DFI_SCHEMAS});

  IF lc_count = ${DFI_SCHEMAS_NO}
  THEN

    SELECT COUNT(*)
    INTO lc_count
    FROM dba_directories
    WHERE directory_name = 'DATA_PUMP_DIR'
    AND directory_path = '/u01/app/oracle/admin/${ORACLE_SID}/dpdump/test';

    IF lc_count = 0
    THEN
      EXECUTE IMMEDIATE q'[CREATE OR REPLACE DIRECTORY DATA_PUMP_DIR AS '/u01/app/oracle/admin/${ORACLE_SID}/dpdump/']';
    END IF;

    lc_dp_handle := DBMS_DATAPUMP.open(operation => lc_job_mode, job_mode => 'SCHEMA', job_name => lc_job_name, version => 'LATEST');

    IF lc_job_mode = 'EXPORT'
    THEN
       DBMS_DATAPUMP.add_file(handle => lc_dp_handle, filename => lc_dump_name||'.dmp', directory => 'DATA_PUMP_DIR',filetype => lc_dump_type, reusefile => 1);
    ELSIF lc_job_mode = 'IMPORT'
    THEN

      -- To avoid ORA-31684: Object type ... already exists errors, drop objects prior import with the
      -- exception of tables. Only squences have been identified so far, other object types maybe included
      -- in the future
      FOR d IN ( SELECT  'DROP '||object_type||' '||owner||'.'||object_name cmd
                FROM dba_objects
                WHERE owner IN (${DFI_SCHEMAS})
                AND object_type IN ('SEQUENCE'))
      LOOP
        EXECUTE IMMEDIATE d.cmd;
      END LOOP;

      DBMS_DATAPUMP.metadata_filter(handle => lc_dp_handle, name => 'EXCLUDE_PATH_LIST', value => q'['USER']');
      DBMS_DATAPUMP.set_parameter(lc_dp_handle, 'TABLE_EXISTS_ACTION','REPLACE');
      DBMS_DATAPUMP.add_file(handle => lc_dp_handle, filename => lc_dump_name||'.dmp', directory => 'DATA_PUMP_DIR',filetype => lc_dump_type);

    END IF;

    DBMS_DATAPUMP.add_file(handle => lc_dp_handle, filename => lc_job_name||'.log', directory => 'DATA_PUMP_DIR', filetype => lc_log_type);
    DBMS_DATAPUMP.metadata_filter(handle => lc_dp_handle, name => 'SCHEMA_LIST', value => q'[${DFI_SCHEMAS}]');
    DBMS_DATAPUMP.start_job(lc_dp_handle);
    DBMS_DATAPUMP.wait_for_job(handle => lc_dp_handle, job_state => lc_job_state );

    DBMS_OUTPUT.PUT_LINE(lc_job_state);

  ELSE

    DBMS_OUTPUT.PUT_LINE('NODFISCHEMAS');

  END IF;

END;
/
EOF