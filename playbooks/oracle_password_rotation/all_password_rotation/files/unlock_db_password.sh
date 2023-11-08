#!/bin/bash
#
#  Unlock Database Password
#

. ~/.bash_profile

[[ ! -z ${DB_NAME} ]] && CONNECT="@${DB_NAME}"
[[ -z ${LOGIN_USER} ]] && SYSDBA="as sysdba"

sqlplus -S /nolog <<EOSQL
connect ${LOGIN_USER}/${LOGIN_PWD}${CONNECT} ${SYSDBA}
set trimspool on
set pages 0
set lines 30
set feedback off
whenever sqlerror exit failure
ALTER USER ${DB_USERNAME} ACCOUNT UNLOCK;
exit;
EOSQL
