#!/bin/bash
#
#  Get Alfresco Wallet location
#
. ~oracle/.bash_profile

sqlplus -s /  as sysdba <<EOF
SET LINES 1000
SET PAGES 0
SET FEEDBACK OFF
SET HEADING OFF
WHENEVER SQLERROR EXIT FAILURE

SELECT REPLACE(value_string,'file:','')
FROM   delius_app_schema.spg_control
WHERE  control_code='ALFWALLET';

EXIT
EOF