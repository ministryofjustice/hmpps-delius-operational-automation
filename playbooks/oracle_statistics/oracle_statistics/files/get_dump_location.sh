#!/bin/bash
#
#  Get path to Export File
#

DIRECTORY_NAME=$1

. ~/.bash_profile

sqlplus -s /nolog <<EOSQL
connect / as sysdba

WHENEVER SQLERROR EXIT FAILURE
SET FEEDBACK OFF
SET SERVEROUT ON
SET HEADING OFF
SET PAGES 0

SELECT directory_path
FROM   dba_directories
WHERE  directory_name = 'DATA_PUMP_DIR';

EXIT
EOSQL