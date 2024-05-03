#!/bin/bash
#
#  Check if delius_app_schema exists
# 

. ~/.bash_profile

sqlplus -s / as sysdba <<EOSQL
SET FEEDBACK OFF
SET HEADING OFF
SET PAGES 0
SET TRIMSPOOL ON
WHENEVER SQLERROR EXIT FAILURE

SELECT COUNT(*)
FROM dba_users
WHERE username = 'DELIUS_APP_SCHEMA';

EXIT
EOSQL