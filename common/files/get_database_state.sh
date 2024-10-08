#!/bin/bash

. ~/.bash_profile

sqlplus -s / as sysdba <<EOSQL
SET FEEDBACK OFF
SET HEADING OFF
SET PAGES 0
SELECT open_mode
FROM v\$database;
EOSQL
exit