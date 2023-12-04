#!/bin/bash

. ~/.bash_profile

sqlplus -s / as sysdba << EOF

SET LINES 132
SET PAGES 0
SET FEEDBACK OFF
SET HEADING OFF
WHENEVER SQLERROR EXIT FAILURE;

SELECT database_role||','||open_mode
FROM   v\$database;

EXIT
EOF