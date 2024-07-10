#!/bin/bash

[[ -z ${NUMBER_OF_YEARS} ]] && echo "NUMBER_OF_YEARS must be specified" && exit 1

. ~/.bash_profile

sqlplus -s /  as sysdba <<EOF
SET LINES 1000
SET PAGES 0
SET FEEDBACK OFF
SET HEADING OFF
WHENEVER SQLERROR EXIT FAILURE
CREATE FLASHBACK ARCHIVE delius_${NUMBER_OF_YEARS}_year_fda TABLESPACE t_flashback_data_archive RETENTION ${NUMBER_OF_YEARS} YEAR;
EXIT
EOF