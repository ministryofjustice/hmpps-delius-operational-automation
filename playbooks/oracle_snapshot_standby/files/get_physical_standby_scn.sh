#!/bin/bash

. ~/.bash_profile

sqlplus -s / as sysdba <<EOF
SET LINES 1000
SET PAGES 0
SET FEEDBACK OFF
SET HEADING OFF
WHENEVER SQLERROR EXIT FAILURE
COL current_scn FORMAT 99999999999999
SELECT current_scn 
FROM v\$database;
EXIT
EOF