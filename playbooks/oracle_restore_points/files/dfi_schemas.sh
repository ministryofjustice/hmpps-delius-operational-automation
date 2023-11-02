#!/bin/bash 
 
 . ~/.bash_profile

ACTION=${1}

sqlplus -s / as sysdba << EOF

DECLARE

lc_count  INTEGER(1);

BEGIN

  SELECT COUNT(*)
  INTO lc_count
  FROM dba_directories
  WHERE directory_name = 'DATA_PUMP_DIR'
  AND directory_path = '/u01/app/oracle/admin/${ORACLE_SID}/dpdump/';

  IF lc_count = 0
  THEN
    EXECUTE IMMEDIATE q'[CREATE OR REPLACE DIRECTORY data_pump_dir AS '/u01/app/oracle/admin/${ORACLE_SID}/dpdump/']';
  END IF;
END;
/
EOF


if [ "${ACTION}" == "export" ]
then
  expdp \"/ as sysdba\" schemas=dfimis_landing,dfimis_subscriber,dfimis_data,dfimis_working,dfimis_loader,dfimis_abc directory=data_pump_dir dumpfile=dfischemas.dmp logfile=expdfischemas.log job_name=expdfischemas reuse_dumpfiles=y
elif [ "${ACTION}" == "import" ]
then

  # To avoid ORA-31684: Object type ... already exists errors, drop objects prior import with the 
  # exception of tables. Only squences have been identified so far, other object types maybe included
  # in the future
  sqlplus -s / as sysdba << EOF

  BEGIN

    FOR d IN ( SELECT  'DROP '||object_type||' '||owner||'.'||object_name cmd
               FROM dba_objects 
               WHERE owner IN (
                'DFIMIS_LANDING',
                'DFIMIS_SUBSCRIBER',
                'DFIMIS_DATA',
                'DFIMIS_WORKING',
                'DFIMIS_LOADER',
                'DFIMIS_ABC')
               AND object_type IN ('SEQUENCE'))
      LOOP
        EXECUTE IMMEDIATE d.cmd;
      END LOOP;
  END;
  /
EOF

  impdp \"/ as sysdba\" schemas=dfimis_landing,dfimis_subscriber,dfimis_data,dfimis_working,dfimis_loader,dfimis_abc exclude=user directory=data_pump_dir dumpfile=dfischemas.dmp job_name=impdfischemas table_exists_action=replace logfile=impdfischemas.log
fi