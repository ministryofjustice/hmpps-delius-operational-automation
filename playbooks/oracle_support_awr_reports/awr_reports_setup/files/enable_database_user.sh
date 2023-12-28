#!/bin/bash

. ~/.bash_profile

DB_USER="SYS\$UMF"
DBA_PASSWORDS=$(aws secretsmanager get-secret-value --secret-id ${SECRET_ID} --query SecretString --output text)
SYSUMF_PASSWORD=$(aws secretsmanager get-secret-value --secret-id ${SECRET_ID} --query SecretString --output text | jq -r .sysumf)

function random () {
  LC_CTYPE=C
  CHAR_TYPE="$1"
  LENGTH=$2
  tr -dc ${1}  </dev/urandom | head -c ${2}
}

if [[ "${SYSUMF_PASSWORD}" == "null" || -z ${SYSUMF_PASSWORD} ]]
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

  # User does not exist in secret
  [ "${SYSUMF_PASSWORD}" == "null" ] && ADD_PASSWORD="${DBA_PASSWORDS/\}/,\"sysumf\":\"${DB_PASS}\"\}}"
  # User exists in secret with no password
  [ -z ${SYSUMF_PASSWORD} ] && ADD_PASSWORD=$(echo $DBA_PASSWORDS | sed 's/\(^.*\)\("sysumf":\)\(""\)\(.*$\)/\1\2"'${DB_PASS}'"\4/')
  aws secretsmanager update-secret --secret-id ${SECRET_ID} --secret-string ${ADD_PASSWORD}

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