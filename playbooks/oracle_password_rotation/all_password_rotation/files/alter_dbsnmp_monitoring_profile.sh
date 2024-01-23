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
BEGIN
    EXECUTE IMMEDIATE 'ALTER PROFILE dbsnmp_monitoring_profile LIMIT password_rollover_time 0.05';
END;
/
exit;
EOSQL
