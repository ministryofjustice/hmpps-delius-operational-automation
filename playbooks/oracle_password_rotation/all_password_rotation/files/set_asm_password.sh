#!/bin/bash
#
#  Set ASM Password
#

. ~/.bash_profile

PATH=$PATH:/usr/local/bin

# Check secret name if it belongs to OEM because the username for the sys password is different

ASM_PASSWORD=$(aws secretsmanager get-secret-value --secret-id ${SECRET_NAME} --region eu-west-2 --query SecretString --output text| jq -r .${ASM_USERNAME})

export ORACLE_SID=+ASM
export ORAENV_ASK=NO

. oraenv

sqlplus -S /nolog <<EOSQL
connect / as sysasm
set pages 0
set lines 30
set echo on
whenever sqlerror exit failure
ALTER USER ${ASM_USERNAME} IDENTIFIED BY ${ASM_PASSWORD};
exit;
EOSQL
