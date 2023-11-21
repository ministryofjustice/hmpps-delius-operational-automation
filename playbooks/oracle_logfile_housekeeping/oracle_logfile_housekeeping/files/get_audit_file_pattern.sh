#!/bin/bash
#
#  Get location of OS Audit Location (adump)
#
. ~oracle/.bash_profile

sqlplus -s /  as sysdba <<EOF
SET LINES 1000
SET PAGES 0
SET FEEDBACK OFF
SET HEADING OFF
WHENEVER SQLERROR EXIT FAILURE

SELECT value
FROM   v\$parameter
WHERE  name = 'audit_file_dest';

EXIT
EOF