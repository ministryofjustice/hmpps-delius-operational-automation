#!/bin/bash
#
#  Set Database Password
#

. ~/.bash_profile

DB_PASSWORD=$(aws secretsmanager get-secret-value --secret-id ${SECRET_NAME} --region eu-west-2 --query SecretString --output text| jq -r .${DB_USERNAME})

sqlplus -S / as sysdba <<EOSQL
set pages 0
set lines 30
set echo on
whenever sqlerror exit failure
-- Oracle will only accept 2 passwords during Gradual Database Password Rollover Period
-- The original password and the new password; if you change the password again then
-- intervening passwords will not be accepted. 
ALTER USER ${DB_USERNAME} IDENTIFIED BY ${DB_PASSWORD} ACCOUNT UNLOCK;
exit;
EOSQL
