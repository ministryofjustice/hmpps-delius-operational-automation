#!/bin/bash

. ~/.bash_profile

sqlplus -s /  as sysdba <<EOF
SET LINES 1000
SET PAGES 0
SET FEEDBACK OFF
SET HEADING OFF
WHENEVER SQLERROR EXIT FAILURE
SELECT tablespace_name
FROM   dba_tablespaces
WHERE  tablespace_name = 'T_FLASHBACK_DATA_ARCHIVE';
EXIT
EOF