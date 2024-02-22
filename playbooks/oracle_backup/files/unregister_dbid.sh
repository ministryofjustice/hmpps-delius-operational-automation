#!/bin/bash

get_rman_password () {
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ASSUME_ROLE_NAME}"
  SESSION="catalog-ansible"
  CREDS=$(aws sts assume-role --role-arn "${ROLE_ARN}" --role-session-name "${SESSION}"  --output text --query "Credentials.[AccessKeyId,SecretAccessKey,SessionToken]")
  export AWS_ACCESS_KEY_ID=$(echo "${CREDS}" | tail -1 | cut -f1)
  export AWS_SECRET_ACCESS_KEY=$(echo "${CREDS}" | tail -1 | cut -f2)
  export AWS_SESSION_TOKEN=$(echo "${CREDS}" | tail -1 | cut -f3)
  SECRET_ARN="arn:aws:secretsmanager:eu-west-2:${SECRET_ACCOUNT_ID}:secret:${SECRET}"
  RMANPASS=$(aws secretsmanager get-secret-value --secret-id "${SECRET_ARN}" --query SecretString --output text | jq -r .rcvcatowner)
}

export DBID=$1

. ~/.bash_profile

if [[ "${CATALOG}" != "NOCATALOG" ]]
then
   get_rman_password
   CONNECT_TO_CATALOG="connect catalog ${CONNECT_TO_CATALOG}"
fi

rman <<EOF
set echo on
${CONNECT_TO_CATALOG};
set DBID ${DBID};
unregister database noprompt;
EOF
