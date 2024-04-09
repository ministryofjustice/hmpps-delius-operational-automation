#!/bin/bash

PATH=$PATH:/usr/local/bin
ORAENV_ASK=NO
ORACLE_SID=${CATALOG_DB}
. oraenv > /dev/null 2>&1
RMANPASS=$(aws secretsmanager get-secret-value --secret-id "/oracle/database/${CATALOG_DB}/shared-passwords" --query SecretString --output text | jq -r .rcvcatowner)

sqlplus -s /  as sysdba <<EOF
SET LINES 1000
SET PAGES 0
SET FEEDBACK OFF
SET HEADING OFF
WHENEVER SQLERROR EXIT FAILURE
ALTER USER ${NEW_CATALOG_SCHEMA} IDENTIFIED BY ${RMANPASS};
EOF