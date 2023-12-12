#!/bin/bash
# Check the Database role

. ~/.bash_profile

sqlplus -s / as sysdba <<EOSQL
SET HEADING OFF
SELECT database_role
FROM   v\$database;
EXIT
EOSQL
