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
WHERE  tablespace_name = 'STATSPACK_DATA';
EXIT
EOF