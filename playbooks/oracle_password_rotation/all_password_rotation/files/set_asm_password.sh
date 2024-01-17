#!/bin/bash
#
#  Set ASM Password
#

. ~/.bash_profile

PATH=$PATH:/usr/local/bin

# Check secret name if it belongs to OEM because the username for the sys password is different

ASMSNMP_PASSWORD=$(aws secretsmanager get-secret-value --secret-id ${SECRET_NAME} --region eu-west-2 --query SecretString --output text| jq -r .${ASM_USERNAME})
SYS_PASSWORD=$(aws secretsmanager get-secret-value --secret-id ${SECRET_NAME} --region eu-west-2 --query SecretString --output text| jq -r .${SYS_USERNAME})

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
