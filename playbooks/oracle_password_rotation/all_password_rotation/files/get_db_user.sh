#!/bin/bash

. ~/.bash_profile

sqlplus -S / as sysdba <<EOSQL
set trimspool on
set pages 0
set lines 30
set feedback off
SELECT
    COUNT(*)
FROM
    dba_users
WHERE
    username = UPPER('${DB_USERNAME}');
exit;
EOSQL
