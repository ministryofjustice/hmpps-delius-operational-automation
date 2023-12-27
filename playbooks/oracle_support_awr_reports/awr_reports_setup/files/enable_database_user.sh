#!/bin/bash

. ~/.bash_profile

DB_USER="SYS\$UMF"

INSTANCEID=$(wget -q -O - http://169.254.169.254/latest/meta-data/instance-id)
ENVIRONMENT_NAME=$(aws ec2 describe-tags --filters "Name=resource-id,Values=${INSTANCEID}" "Name=key,Values=environment-name"  --query "Tags[].Value" --output text)
DELIUS_ENVIRONMENT=$(aws ec2 describe-tags --filters "Name=resource-id,Values=${INSTANCEID}" "Name=key,Values=delius-environment"  --query "Tags[].Value" --output text)
APPLICATION=$(aws ec2 describe-tags --filters "Name=resource-id,Values=${INSTANCEID}" "Name=key,Values=application"  --query "Tags[].Value" --output text)
SYSUMF_PASSWORD=$(aws secretsmanager get-secret-value --secret-id ${ENVIRONMENT_NAME}-${DELIUS_ENVIRONMENT}-${APPLICATION}-dba-passwords --region {{ region }} --query SecretString --output text| jq -r .sysumf)

function random () {
  LC_CTYPE=C
  CHAR_TYPE="$1"
  LENGTH=$2
  tr -dc ${1}  </dev/urandom | head -c ${2}
}

if [[ -z $[SYSUMF_PASSWORD} ]]
then
    # Leading Character May Only Be ASCII
    PASSWORD_LEADING=$(random [:alpha:] 1)

    # Need at Least One Lower Case Character
    PASSWORD_CHARS=$(random [:lower:] 1)

    # Need at Least One Upper Case Character
    PASSWORD_CHARS+=$(random [:upper:] 1)

    # Need at Least One Digit Character
    PASSWORD_CHARS+=$(random [:digit:] 1)

    # Need at Least One Special Character
    PASSWORD_CHARS+=$(random _# 1)

    # Get Remaining Length
    REMAINING_CHARACTERS=$((${PASSWORD_LENGTH} - 5))

    # Use Random Characters for remainder of the password
    PASSWORD_CHARS+=$(random [:lower:][:upper:][:digit:]_# $REMAINING_CHARACTERS)

    DB_PASS=${PASSWORD_LEADING}${PASSWORD_CHARS}
else
    DB_PASS=${SYSUMF_PASSWORD}
fi

sqlplus -s / as sysdba << EOF

SET LINES 132
SET PAGES 0
SET FEEDBACK OFF
SET HEADING OFF
WHENEVER SQLERROR EXIT FAILURE;

ALTER USER ${DB_USER} ACCOUNT UNLOCK;
ALTER USER ${DB_USER} IDENTIFIED BY ${DB_PASS};

EXIT
EOF