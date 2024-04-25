#!/bin/bash
# Check the Count of Any Restore Points

. ~/.bash_profile

if [[ $(grep ^${ORACLE_SID}: /etc/oratab | wc -l ) -eq 0 ]]
then
    echo 0
else
    sqlplus -s / as sysdba <<EOSQL 
    SET HEADING OFF
    WHENEVER SQLERROR EXIT FAILURE
    SELECT COUNT(*)
    FROM   v\$restore_point;
    EXIT
EOSQL
fi
