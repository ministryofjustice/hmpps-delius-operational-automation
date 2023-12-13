#!/bin/bash

. ~/.bash_profile

sqlplus -s /  as sysdba <<EOF
SET LINES 1000
SET PAGES 0
SET FEEDBACK OFF
SET HEADING OFF
WHENEVER SQLERROR EXIT FAILURE
SELECT property_value
FROM   database_properties
WHERE  property_name  = 'DEFAULT_TEMP_TABLESPACE';
EXIT
EOF