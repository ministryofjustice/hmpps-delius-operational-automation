#!/bin/bash

[[ -z ${NUMBER_OF_YEARS} ]] && echo "NUMBER_OF_YEARS must be specified" && exit 1

. ~/.bash_profile

sqlplus -s /  as sysdba <<EOF
SET LINES 1000
SET PAGES 0
SET FEEDBACK OFF
SET HEADING OFF
WHENEVER SQLERROR EXIT FAILURE
SELECT flashback_archive_name
FROM   dba_flashback_archive
WHERE  flashback_archive_name = 'DELIUS_${NUMBER_OF_YEARS}_YEAR_FDA';
EXIT
EOF