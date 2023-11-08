#!/bin/bash
#
#  Set ASM Password
#

. ~/.bash_profile

export ORACLE_SID=+ASM
export ORAENV_ASK=NO

. oraenv

sqlplus -S /nolog <<EOSQL
connect / as sysasm
set pages 0
set lines 30
set echo on
whenever sqlerror exit failure
ALTER USER sys IDENTIFIED BY ${SYS_PASSWORD};
ALTER USER asmsnmp IDENTIFIED BY ${ASMSNMP_PASSWORD};
exit;
EOSQL
