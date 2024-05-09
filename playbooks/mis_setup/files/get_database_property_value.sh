#!/bin/bash

. ~/.bash_profile

PROPERTY_NAME=${1}

sqlplus -s / as sysdba << EOF
SET LINES 132
SET PAGES 0
SET FEEDBACK OFF
SET HEADING OFF
WHENEVER SQLERROR EXIT FAILURE
SELECT property_value
FROM database_properties
WHERE property_name = UPPER('${PROPERTY_NAME}');
EXIT 
EOF