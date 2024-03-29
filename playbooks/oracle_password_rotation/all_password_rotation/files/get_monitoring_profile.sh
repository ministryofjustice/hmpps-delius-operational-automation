#!/bin/bash

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
SELECT
    profile
FROM
    dba_profiles
WHERE
    profile = '${PROFILE_NAME}'
FETCH NEXT 1 ROW ONLY;
exit;
EOSQL
