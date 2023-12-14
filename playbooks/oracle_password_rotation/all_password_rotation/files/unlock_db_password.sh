#!/bin/bash
#
#  Unlock Database Password
#

. ~/.bash_profile

sqlplus -S / as sysdba <<EOSQL
set trimspool on
set pages 0
set lines 30
set feedback off
whenever sqlerror exit failure
ALTER USER ${DB_USERNAME} ACCOUNT UNLOCK;
exit;
EOSQL
