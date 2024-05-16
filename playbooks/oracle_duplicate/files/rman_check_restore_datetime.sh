#!/bin/bash
. ~/.bash_profile
SOURCE_DB=$1
CATALOG_DB=$2
CATALOG_SCHEMA=$3
RESTORE_DATETIME=${4:-NONE}
DATEFORMAT='YYMMDDHH24MISS'

# Determine the rman password depending where the catalog database resides
if [[ ! ${CATALOG_DB} =~ ^\(DESCRIPTION.* ]]
then
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ASSUME_ROLE_NAME}"
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
else
  INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
  APPLICATION=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$INSTANCE_ID" "Name=key,Values=application" --query 'Tags[0].Value' --output text)
  RMANUSER=rman19c
  if [ "$APPLICATION" == "delius" ]
  then
    SECRET_ID="${ENVIRONMENT_NAME}-oracle-db-dba-passwords"
  elif [ "$APPLICATION" == "delius-mis" ]
  then
    DATABASE_TYPE=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$INSTANCE_ID" "Name=key,Values=database" --query 'Tags[0].Value' --output text | cut -d'_' -f1)
    SECRET_ID="${ENVIRONMENT_NAME}-oracle-${DATABASE_TYPE}-db-dba-passwords"
    echo ${SECRET_ID}
  fi
  RMANPASS=$(aws secretsmanager get-secret-value --secret-id ${SECRET_ID} --query SecretString --output text | jq -r .rman)
fi

if [ -z ${RMANPASS} ]
then
  echo "Password for rman in secrets does not exist"
  exit 1
fi

CATALOG_CONNECT=${RMANUSER}/${RMANPASS}@${CATALOG_DB}

if [ "${RESTORE_DATETIME}" != "NONE" ]
then

sqlplus -s ${CATALOG_CONNECT} << EOF
whenever sqlerror exit failure
set feedback off heading off pages 0 verify off echo off
col c format 9
select trim(count(*)) c
from (select min(decode(btyp,'FULL',btim,null)) full_time
            ,max(decode(btyp,'ARCH',btim,null))	arch_time
        from (select 'FULL' btyp
                     ,btim
                from (select min(bp.completion_time) btim
                      from rc_database d
                         ,rc_backup_piece bp
                      where bp.db_key = d.db_key
                      and bp.backup_type in ('D','I')
                      and d.name = upper('${SOURCE_DB}')
                      and bp.incremental_level = 0)
              union
              select 'ARCH' btyp
                    ,btim
                from (select max(bp.completion_time) btim
                        from rc_database d
                            ,rc_backup_piece bp
                        where bp.db_key = d.db_key
                        and bp.backup_type = 'L'
                        and d.name = upper('${SOURCE_DB}'))
        )
     )
where full_time <= to_date('${RESTORE_DATETIME}','${DATEFORMAT}')
and   arch_time >= to_date('${RESTORE_DATETIME}','${DATEFORMAT}')
/
EOF

fi