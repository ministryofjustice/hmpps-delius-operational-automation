#!/bin/bash
#
#  Get Alfresco URL currently configured
#
. ~oracle/.bash_profile

sqlplus -s /  as sysdba <<EOF
SET LINES 1000
SET PAGES 0
SET FEEDBACK OFF
SET HEADING OFF
WHENEVER SQLERROR EXIT FAILURE

SELECT value_string
FROM   delius_app_schema.spg_control
WHERE  control_code='ALFURL';

EXIT
EOF