#!/bin/bash

. ~/.bash_profile

TSNAME=${1}

sqlplus -s / as sysdba << EOF
SET LINES 132
SET PAGES 0
SET FEEDBACK OFF
SET HEADING OFF
WHENEVER SQLERROR EXIT FAILURE
SELECT LTRIM(COUNT(*))
FROM dba_tablespaces
WHERE tablespace_name = UPPER('${TSNAME}');
EXIT 
EOF