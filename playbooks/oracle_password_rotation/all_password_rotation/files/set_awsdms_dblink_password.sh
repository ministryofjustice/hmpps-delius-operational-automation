#!/bin/bash
#
#  Set the password for the AWSDMS_DBLINK database link used by
#  AWS DMS Endpoints in Delius (username is always DELIUS_AUDIT_DMS_POOL)
#

. ~/.bash_profile

# The delius_audit_dms_pool password is held in the application secret (not the DBA secret)
SECRET_NAME=$(echo ${SECRET_NAME} | sed 's/-dba-/-application-/')
DBLINK_PASSWORD=$(aws secretsmanager get-secret-value --secret-id ${SECRET_NAME} --region eu-west-2 --query SecretString --output text| jq -r .delius_audit_dms_pool)

sqlplus -S /nolog <<EOSQL
connect / as sysdba
set pages 0
set lines 30
set echo on
whenever sqlerror exit failure
BEGIN
   delius_audit_dms_pool.set_db_link_password(
     p_password=>'${DBLINK_PASSWORD}'
     );
END;
/
exit;
EOSQL
