#!/bin/bash

. ~/.bash_profile

sqlplus -S / as sysdba <<EOSQL
set trimspool on
set pages 0
set lines 30
set feedback off
ALTER USER ${PROFILE_USER} PROFILE ${PROFILE_NAME};
exit;
EOSQL
