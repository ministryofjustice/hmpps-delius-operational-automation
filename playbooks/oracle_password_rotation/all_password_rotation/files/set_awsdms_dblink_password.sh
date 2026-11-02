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
set serverout on

/*
    The procedure SET_DB_LINK_PASSWORD is not available prior to migration
    from legacy to modernisation platform so use conditional compilation
    to skip using it if it does not exist yet.
*/

COL proc_exists NEW_VALUE PROC_EXISTS_FLAG

select 'proc_exists:'||CASE WHEN MAX(object_name) IS NULL THEN 'FALSE' ELSE 'TRUE' END proc_exists
from dba_objects
where object_name = 'SET_DB_LINK_PASSWORD';

ALTER SESSION SET PLSQL_CCFLAGS='&PROC_EXISTS_FLAG';

BEGIN
   \$IF \$\$proc_exists \$THEN
   delius_audit_dms_pool.set_db_link_password(
     p_password=>'${DBLINK_PASSWORD}'
     );
   \$ELSE
   DBMS_OUTPUT.put_line('database link password setting procedure does not exist yet');
   \$END
END;
/
exit;
EOSQL
