#!/bin/bash
#
#  DBSNMP_MONITORING_PROFILE is based on ORA_STIG_PROFILE
#  (Oracle Security Technical Implementation Guidelines compliance)

. ~/.bash_profile

[[ ! -z ${DB_NAME} ]] && CONNECT="@${DB_NAME}"
[[ -z ${LOGIN_USER} ]] && SYSDBA="as sysdba"

sqlplus -S /nolog <<EOSQL
connect ${LOGIN_USER}/${LOGIN_PWD}${CONNECT} ${SYSDBA}
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
