#!/bin/bash
#
# This runs on the Snapshot Standby
#
# 1. Create temporary database link to the Primary
# 2. Push additional audit records from the Standby to the Primary
# 3. Drop the database link


# Retrieve passwords for Delius application users
INSTANCEID=$(wget -q -O - http://169.254.169.254/latest/meta-data/instance-id)
ENVIRONMENT_NAME=$(aws ec2 describe-tags --filters "Name=resource-id,Values=${INSTANCEID}" "Name=key,Values=environment-name"  --query "Tags[].Value" --output text)
DELIUS_ENVIRONMENT=$(aws ec2 describe-tags --filters "Name=resource-id,Values=${INSTANCEID}" "Name=key,Values=delius-environment"  --query "Tags[].Value" --output text)
APPLICATION=$(aws ec2 describe-tags --filters "Name=resource-id,Values=${INSTANCEID}" "Name=key,Values=application"  --query "Tags[].Value" --output text)
SECRET_ID=${ENVIRONMENT_NAME}-${DELIUS_ENVIRONMENT}-${APPLICATION}-application-passwords
DELIUS_APP_SCHEMA_PASSWORD=$(aws secretsmanager get-secret-value --secret-id ${SECRET_ID} --query SecretString --output text| jq -r .delius_app_schema)
DELIUS_POOL_PASSWORD=$(aws secretsmanager get-secret-value --secret-id ${SECRET_ID} --query SecretString --output text| jq -r .delius_pool)

# TNS Alis for Primary Database
PRIMARY_DB=$1
# Date of the Snapshot Conversion (Format YYYY-MM-DD-HH24-MI-SS)
SNAPSHOT_CONVERT_DATE=$2

. ~/.bash_profile

sqlplus -s /nolog <<EOF
SET LINES 1000
SET PAGES 0
SET FEEDBACK ON
SET HEADING ON
SET SERVEROUT ON
WHENEVER SQLERROR EXIT FAILURE

connect delius_app_schema/${DELIUS_APP_SCHEMA_PASSWORD}

DECLARE
   l_link_already_exists INTEGER;
BEGIN
   SELECT COALESCE(MAX(1),0)
   INTO   l_link_already_exists
   FROM   user_db_links
   WHERE  db_link = 'TEMP_LINK_TO_PRIMARY';
   IF l_link_already_exists = 1 THEN
      EXECUTE IMMEDIATE 'DROP DATABASE LINK temp_link_to_primary';
   END IF;
END;
/

CREATE DATABASE LINK temp_link_to_primary
CONNECT TO delius_pool IDENTIFIED BY "${DELIUS_POOL_PASSWORD}"
USING '${PRIMARY_DB}';

COLUMN list_audit_columns NEW_VALUE AUDITCOLUMNS

SELECT   LISTAGG(column_name,',') WITHIN GROUP (ORDER BY column_id) list_audit_columns
FROM     user_tab_columns
WHERE    table_name = 'AUDITED_INTERACTION';

SET ECHO ON

INSERT INTO audited_interaction@temp_link_to_primary (&&AUDITCOLUMNS)
SELECT &&AUDITCOLUMNS
FROM   delius_app_schema.audited_interaction 
WHERE  date_time >= TO_DATE('${SNAPSHOT_CONVERT_DATE}','YYYY-MM-DD-HH24-MI-SS');

COMMIT;

DROP DATABASE LINK temp_link_to_primary;

EXIT
EOF