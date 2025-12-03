#!/bin/bash
#
#  Set ASM Password
#

. ~/.bash_profile

PATH=$PATH:/usr/local/bin

# The DELIUS_AUDIT_DMS_POOL ASM account password is held in a different Secret from the other ASM accounts
# as it uses the same password as the DELIUS_AUDIT_DMS_POOL database user.
if [[ "${ASM_USERNAME}" == "delius_audit_dms_pool" ]]
then
   SECRET_NAME=$(echo ${SECRET_NAME} | sed 's/-dba-/-application-/')
fi
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
