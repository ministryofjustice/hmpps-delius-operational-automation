#!/bin/bash
#
# Query which returns a CSV list of:
#   Table Owner (input)
#   Table Name (input)
#   Whether flashback retention is set correctly

[[ -z ${OWNER_NAME} ]] && echo "Table OWNER_NAME must be specified" && exit 1
[[ -z ${TABLE_NAME} ]] && echo "TABLE_NAME must be specified" && exit 1
[[ -z ${NUMBER_OF_YEARS} ]] && echo "NUMBER_OF_YEARS must be specified" && exit 1

. ~/.bash_profile

sqlplus -s /  as sysdba <<EOF
SET LINES 1000
SET PAGES 0
SET FEEDBACK OFF
SET HEADING OFF
WHENEVER SQLERROR EXIT FAILURE
SELECT owner_name||','||table_name||','||
       CASE WHEN REGEXP_REPLACE(flashback_archive_name,'DELIUS_(\d+)_YEAR_FDA','\1') = ${NUMBER_OF_YEARS}
       THEN 'CORRECT_RETENTION'
       ELSE 'INCORRECT_RETENTION'
       END
FROM   dba_flashback_archive_tables
WHERE  owner_name = '${OWNER_NAME}'
AND    table_name = '${TABLE_NAME}';
EXIT
EOF