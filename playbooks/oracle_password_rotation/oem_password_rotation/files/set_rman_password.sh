#!/bin/bash

. ~/.bash_profile

PATH=$PATH:/usr/local/bin
ORAENV_ASK=NO
ORACLE_SID=${DB_NAME}
. oraenv
ORAENV_ASK=YES

RMAN_PASSWORD=$(aws secretsmanager get-secret-value --secret-id ${SECRET_ID} --region eu-west-2 --query SecretString --output text| jq -r .rman)

sqlplus /nolog <<EOSQL
connect / as sysdba
alter user rman identified by ${RMAN_PASSWORD};
exit;
EOSQL
