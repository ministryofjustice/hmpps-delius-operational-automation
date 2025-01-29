#!/bin/bash

. ~/.bash_profile

# Restore Archivelogs Up to the requested MAX_SEQNO
[[ -z $MAX_SEQNO ]] && echo "The Maximum Sequence Number to restore archivelogs to must be supplied" && exit 9

# Get the RMAN Catalog Password
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${OEM_SECRET_ROLE}"
SESSION="catalog-ansible"
SECRET_ACCOUNT_ID=$(aws ssm get-parameters --with-decryption --name account_ids | jq -r .Parameters[].Value |  jq -r 'with_entries(if (.key|test("hmpps-oem.*$")) then ( {key: .key, value: .value}) else empty end)' | jq -r 'to_entries|.[0].value' )
CREDS=$(aws sts assume-role --role-arn "${ROLE_ARN}" --role-session-name "${SESSION}"  --output text --query "Credentials.[AccessKeyId,SecretAccessKey,SessionToken]")
export AWS_ACCESS_KEY_ID=$(echo "${CREDS}" | tail -1 | cut -f1)
export AWS_SECRET_ACCESS_KEY=$(echo "${CREDS}" | tail -1 | cut -f2)
export AWS_SESSION_TOKEN=$(echo "${CREDS}" | tail -1 | cut -f3)
SECRET_ARN="arn:aws:secretsmanager:eu-west-2:${SECRET_ACCOUNT_ID}:secret:/oracle/database/${CATALOG_DB}/shared-passwords"
RMANUSER=${CATALOG_SCHEMA:-rcvcatowner}
RMANPASS=$(aws secretsmanager get-secret-value --secret-id "${SECRET_ARN}" --query SecretString --output text | jq -r .rcvcatowner)
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

# Get Number of CPUs Available on this Host
CPU_COUNT=$(grep -c processor /proc/cpuinfo)

# We are going to overwrite the default level of tape parallelism, so keep a note of the
# previous value so we can reset it afterwards
DEFAULT_PARALLELISM=$(echo "show device type;" | rman target / | grep "'SBT_TAPE'" | grep -oP '(?<=PARALLELISM )\d+')

rman target / <<EOL/
connect catalog rcvcatowner/$RMANPASS@${CATALOG_DB}
# We can max out the CPUs for restoring archivelogs as nobody will be using the DB when we run this
CONFIGURE DEVICE TYPE 'SBT_TAPE' PARALLELISM ${CPU_COUNT};
restore archivelog until sequence ${MAX_SEQNO};
# Reset parallelism to what it was before
CONFIGURE DEVICE TYPE 'SBT_TAPE' PARALLELISM ${DEFAULT_PARALLELISM};
exit
EOL
