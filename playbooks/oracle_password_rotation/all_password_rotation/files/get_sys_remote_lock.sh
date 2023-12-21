#!/bin/bash
#  Check that SYS Password works for remote connection

. ~/.bash_profile

[[ "${DB_NAME}" == "NONE" ]] && exit 0

INSTANCEID=$(wget -q -O - http://169.254.169.254/latest/meta-data/instance-id)
ENVIRONMENT_NAME=$(aws ec2 describe-tags --filters "Name=resource-id,Values=${INSTANCEID}" "Name=key,Values=environment-name"  --query "Tags[].Value" --output text)
DELIUS_ENVIRONMENT=$(aws ec2 describe-tags --filters "Name=resource-id,Values=${INSTANCEID}" "Name=key,Values=delius-environment"  --query "Tags[].Value" --output text)
APPLICATION=$(aws ec2 describe-tags --filters "Name=resource-id,Values=${INSTANCEID}" "Name=key,Values=application"  --query "Tags[].Value" --output text)
SYS_PASSWORD=$(aws secretsmanager get-secret-value --secret-id ${ENVIRONMENT_NAME}-${DELIUS_ENVIRONMENT}-${APPLICATION}-dba-passwords --query SecretString --output text| jq -r .sys)

EXITCODE=$(sqlplus -S /nolog <<EOSQL
connect sys/${SYS_PASSWORD}@${DB_NAME} as sysdba
exit
EOSQL
)

echo $EXITCODE
