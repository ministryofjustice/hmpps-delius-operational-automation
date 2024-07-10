#!/bin/bash

[[ -z ${OWNER_NAME} ]] && echo "Table OWNER_NAME must be specified" && exit 1
[[ -z ${TABLE_NAME} ]] && echo "TABLE_NAME must be specified" && exit 1

. ~/.bash_profile

sqlplus -s /  as sysdba <<EOF
SET LINES 1000
SET PAGES 0
SET FEEDBACK OFF
SET HEADING OFF
WHENEVER SQLERROR EXIT FAILURE
SELECT owner_name||','||table_name
FROM   dba_flashback_archive_tables
WHERE  owner_name = '${OWNER_NAME}'
AND    table_name = '${TABLE_NAME}';
EXIT
EOF