#!/bin/bash
#
# We use a random password for the PERFSTAT user as we do not need to login to
# this account, so the password does not need to be stored, and the account is
# locked after creation.

. ~/.bash_profile

# Spool SQL output to /tmp
cd /tmp

sqlplus -s /  as sysdba <<EOF
SET LINES 1000
SET PAGES 0
SET FEEDBACK OFF
SET HEADING OFF
WHENEVER SQLERROR EXIT FAILURE
DEFINE perfstat_password=p#$(openssl rand -base64 15)
DEFINE default_tablespace=STATSPACK_DATA
DEFINE temporary_tablespace=$2
@?/rdbms/admin/spcreate
EXIT
EOF