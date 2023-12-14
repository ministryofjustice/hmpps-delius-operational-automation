#!/bin/bash

. ~/.bash_profile

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
