#!/bin/bash

. ~/.bash_profile

PATH=$PATH:/usr/local/bin
ORAENV_ASK=NO
ORACLE_SID=${CATALOG_DB}
. oraenv > /dev/null 2>&1

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