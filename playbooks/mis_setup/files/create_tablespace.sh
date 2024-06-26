#!/bin/bash

. ~/.bash_profile

TSNAME=${1}

# echo "CREATE TABLESPACE ${TSNAME};"

sqlplus -s / as sysdba << EOF
SET LINES 132
SET PAGES 0
SET FEEDBACK OFF
SET HEADING OFF
WHENEVER SQLERROR EXIT FAILURE
CREATE TABLESPACE ${TSNAME};
EOF
