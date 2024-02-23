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

. ~/.bash_profile

NAME=${1}

get_rman_password
CONNECT_CATALOG="rcvcatowner/${RMANPASS}@${CATALOG}"

sqlplus -s ${CONNECT_CATALOG}<<EOF
WHENEVER SQLERROR EXIT FAILURE;
SET PAGES 0
SET FEEDBACK OFF
SET HEADING OFF
SET SERVEROUT ON

SELECT LTRIM(COUNT(*))
FROM rc_database
WHERE name = UPPER('${NAME}');

EOF

# If the above fails with an error, do not fail the script
# but simply return a 0 to indicate that the database is not registered
[[ $? -gt 0 ]] && echo 0

exit 0