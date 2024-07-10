#!/bin/bash

[[ -z ${OWNER_NAME} ]] && echo "Table OWNER_NAME must be specified" && exit 1
[[ -z ${TABLE_NAME} ]] && echo "TABLE_NAME must be specified" && exit 1
[[ -z ${NUMBER_OF_YEARS} ]] && echo "NUMBER_OF_YEARS of retention must be specified" && exit 1

. ~/.bash_profile

sqlplus -s /  as sysdba <<EOF
SET LINES 1000
SET PAGES 0
SET FEEDBACK OFF
SET HEADING OFF
WHENEVER SQLERROR EXIT FAILURE
ALTER TABLE ${OWNER_NAME}.${TABLE_NAME} FLASHBACK ARCHIVE delius_${NUMBER_OF_YEARS}_year_fda;
EXIT
EOF