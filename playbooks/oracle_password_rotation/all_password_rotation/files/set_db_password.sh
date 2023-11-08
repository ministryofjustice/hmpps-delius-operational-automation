#!/bin/bash
#
#  Set Database Password
#

. ~/.bash_profile

[[ ! -z ${DB_NAME} ]] && CONNECT="@${DB_NAME}"
[[ -z ${LOGIN_USER} ]] && SYSDBA="as sysdba"

sqlplus -S /nolog <<EOSQL
connect ${LOGIN_USER}/${LOGIN_PWD}${CONNECT} ${SYSDBA}
set pages 0
set lines 30
set echo on
whenever sqlerror exit failure
-- Oracle will only accept 2 passwords during Gradual Database Password Rollover Period
-- The original password and the new password; if you change the password again then
-- intervening passwords will not be accepted. 
ALTER USER ${DB_USERNAME} IDENTIFIED BY ${DB_PASSWORD} ACCOUNT UNLOCK;
exit;
EOSQL
