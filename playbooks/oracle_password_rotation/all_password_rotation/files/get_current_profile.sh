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
    dba_users
WHERE
    username = '${PROFILE_USER}';
exit;
EOSQL
