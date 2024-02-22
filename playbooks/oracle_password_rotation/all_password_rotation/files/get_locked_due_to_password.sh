#!/bin/bash
# Determine if the user account has been locked due to too many failed password attempts.
# This allows us to unlock the account if it is due to OEM/Agent not having their
# password updated in a timely fashion.
# (Not normally need due to Gradual Database Password Rollover, but can happen if
#  passwords are cycled more than once per hour)
#
# Note that PASSWORD_CHANGE_DATE does not appear to be reliable.
#

. ~/.bash_profile

if [[ ! -z ${OEM_DB_NAME} ]]
then
    PATH=$PATH:/usr/local/bin
    ORAENV_ASK=NO
    ORACLE_SID=${OEM_DB_NAME}
    . oraenv > /dev/null 2>&1
fi

sqlplus -S / as sysdba <<EOSQL
set trimspool on
set pages 0
set lines 30
set feedback off
SELECT COALESCE(MAX('YES'),'NO') locked_due_to_password
FROM
    dba_users d
WHERE
        d.username = UPPER('${DB_USERNAME}')
    AND d.account_status LIKE '%LOCKED%'
    AND d.lock_date > d.password_change_date
    AND TRUNC(SYSDATE) = TRUNC(d.password_change_date);
exit;
EOSQL
