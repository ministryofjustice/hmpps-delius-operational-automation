#!/bin/bash
# Check the Count of Any Restore Points

. ~/.bash_profile

sqlplus -s / as sysdba <<EOSQL
SET HEADING OFF
WHENEVER SQLERROR EXIT FAILURE
SELECT COUNT(*)
FROM   v\$restore_point;
EXIT
EOSQL
