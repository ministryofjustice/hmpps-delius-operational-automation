#!/bin/bash

. ~/.bash_profile

sqlplus -s /  as sysdba <<EOF
WHENEVER SQLERROR EXIT FAILURE;
SET FEEDBACK OFF
SET HEADING OFF
SET PAGES 0

SELECT value
FROM v\$option
WHERE parameter = 'Unified Auditing';

EOF