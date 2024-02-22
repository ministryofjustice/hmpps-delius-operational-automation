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

export ORACLE_SID=$1
export DBID=$2

export PATH=$PATH:/usr/local/bin;
export ORAENV_ASK=NO ;
. oraenv >/dev/null;

export NLS_DATE_FORMAT="YYYY-MM-DD HH24:MI:SS"

if [[ "${CATALOG}" != "NOCATALOG" ]]
then
   get_rman_password
   CONNECT_TO_CATALOG="connect catalog rcvcatowner/${RMANPASS}@${CATALOG}"
fi

# Connect to RMAN and find the CURRENT incarnation of the database
rman target / <<EOF | awk -v DBID="${DBID}" '$4~DBID&&$5~/CURRENT/{print $7,$8}'
set echo on
${CONNECT_TO_CATALOG}
list incarnation of database;
EOF
