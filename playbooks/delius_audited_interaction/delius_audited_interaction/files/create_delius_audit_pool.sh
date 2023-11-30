#!/bin/bash
#
#  Create the DELIUS_AUDIT_POOL Account.  This is used to access objects in the DELIUS_AUDIT_SCHEMA which cannot be connected to directly.
#

. ~/.bash_profile

DELIUS_AUDIT_POOL_PASSWORD=$(. /etc/environment && aws ssm get-parameters --region ${REGION} --with-decryption --name /${HMPPS_ENVIRONMENT}/${APPLICATION}/delius-database/db/delius_audit_pool_password | jq -r '.Parameters[].Value')

if [[ -z "${DELIUS_AUDIT_POOL_PASSWORD}" ]]
then
   echo "No password defined for the delius_audit_pool user."
   exit 1
fi

sqlplus /nolog <<EOSQL
connect / as sysdba

WHENEVER SQLERROR EXIT FAILURE;

CREATE USER delius_audit_pool IDENTIFIED BY ${DELIUS_AUDIT_POOL_PASSWORD}
DEFAULT TABLESPACE t_audint_data;

GRANT CREATE SESSION TO delius_audit_pool;

# Allow Checking for Uncommitted Transactions (Lower Bound on Un-Proprogated Data)
GRANT SELECT ON sys.v_\$transaction TO delius_audit_pool;

EXIT
EOSQL