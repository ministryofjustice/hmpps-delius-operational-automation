#!/bin/bash
#  Check that SYS Password works for remote connection

. ~/.bash_profile

[[ "${DB_NAME}" == "NONE" ]] && exit 0

if [[ ! -z ${DB_NAME} ]]
then
    PATH=$PATH:/usr/local/bin
    ORAENV_ASK=NO
    ORACLE_SID=${DB_NAME}
    . oraenv > /dev/null 2>&1
fi

SYS_PASSWORD=$(aws secretsmanager get-secret-value --secret-id ${SECRET_NAME} --query SecretString --output text| jq -r .sys)

EXITCODE=$(sqlplus -S /nolog <<EOSQL
connect sys/${SYS_PASSWORD}@${DB_NAME} as sysdba
exit
EOSQL
)

echo $EXITCODE
