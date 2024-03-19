#!/bin/bash 

. ~/.bash_profile

sqlplus -s / as sysdba << EOF

WHENEVER SQLERROR EXIT FAILURE
SET FEEDBACK OFF
SET HEADING OFF
SET PAGES 0

SELECT dbid
FROM v\$database;

EOF