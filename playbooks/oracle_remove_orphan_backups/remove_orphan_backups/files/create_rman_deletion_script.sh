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
export SCRIPT_FILE=$2

export PATH=$PATH:/usr/local/bin; 
export ORAENV_ASK=NO ; 
. oraenv >/dev/null;

get_rman_password
CATALOG_CONNECT_STRING="connect rcvcatowner/${RMANPASS}@${CATALOG}"

# We can potentially safely remove backupsets for all Orphan incarnations
# but we limit ourselves to those that are also older than the recovery window
sqlplus -s /nolog <<EOF
${CATALOG_CONNECT_STRING}
SET LINES 1000
SET PAGES 0
SET FEEDBACK OFF
SET HEADING OFF
SET TRIMSPOOL ON
WHENEVER SQLERROR EXIT FAILURE
SPOOL ${SCRIPT_FILE}
WITH orphan_incarnations
AS (SELECT       i.db_key
                ,i.dbinc_key
    FROM        dbinc i
    WHERE       i.db_name = '${ORACLE_SID}'
    AND         i.dbinc_status = 'ORPHAN'
    AND         i.reset_time < (SELECT SYSDATE- TO_NUMBER(Regexp_Replace(value,'TO RECOVERY WINDOW OF (\d+) DAYS','\1'))
                                FROM   conf c
                                WHERE  c.db_key = i.db_key
                                AND    name = 'RETENTION POLICY'))
SELECT      DISTINCT 'DELETE NOPROMPT BACKUPSET '||bs_key||';'
FROM        orphan_incarnations o
INNER JOIN  rc_backup_datafile df
ON          o.db_key = df.db_key
AND         o.dbinc_key = df.dbinc_key
UNION ALL
SELECT      DISTINCT 'DELETE NOPROMPT ARCHIVELOG '''||a.name||''';'
FROM        orphan_incarnations o
INNER JOIN  rc_archived_log a
ON          o.db_key = a.db_key
AND         o.dbinc_key = a.dbinc_key
;
SPOOL OFF
EXIT
EOF