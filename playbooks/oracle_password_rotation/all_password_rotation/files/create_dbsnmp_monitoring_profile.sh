#!/bin/bash
#
#  DBSNMP_MONITORING_PROFILE is based on ORA_STIG_PROFILE
#  (Oracle Security Technical Implementation Guidelines compliance)

. ~/.bash_profile

if [[ ! -z ${OEM_DB_NAME} ]]
then
    PATH=$PATH:/usr/local/bin
    ORAENV_ASK=NO
    ORACLE_SID=${OEM_DB_NAME}
    . oraenv > /dev/null 2>&1
fi

sqlplus -S / as sysdba <<EOSQL
set trimspool on
set pages 0
set lines 30
set feedback off
DECLARE
    l_command VARCHAR2(1000);
BEGIN
    SELECT
        'CREATE PROFILE dbsnmp_monitoring_profile LIMIT '
        || LISTAGG(resource_name
                   || ' '
                   || limit, ' ')
    INTO l_command
    FROM
        dba_profiles
    WHERE
            profile = 'ORA_STIG_PROFILE'
        AND limit != 'DEFAULT';

    EXECUTE IMMEDIATE l_command;
    -- Allow up to 1 hour for corresponding password to be updated in OEM
    EXECUTE IMMEDIATE 'ALTER PROFILE dbsnmp_monitoring_profile LIMIT password_rollover_time 0.05';
END;
/
exit;
EOSQL
