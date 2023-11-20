#!/bin/bash

. ~/.bash_profile

# Spool SQL output to /tmp
cd /tmp

sqlplus -s /  as sysdba <<EOF
SET LINES 1000
SET PAGES 0
SET FEEDBACK OFF
SET HEADING OFF
WHENEVER SQLERROR EXIT FAILURE
DEFINE perfstat_password=$1
DEFINE default_tablespace=STATSPACK_DATA
DEFINE temporary_tablespace=$2
@?/rdbms/admin/spcreate
EXIT
EOF