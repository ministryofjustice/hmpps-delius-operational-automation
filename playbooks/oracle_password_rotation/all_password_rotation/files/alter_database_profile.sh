#!/bin/bash
#
# Allow a Gradual Database Password Rollover (GDPR) of 0.05 days (approx 72 minutes).
# During this time the old password may still be used.

. ~/.bash_profile

# We can optionally set additional parameters for this profile if we set these
# environment variables to be non-null
PROFILE_IDLE_TIME=${IDLE_TIME:-0}

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
BEGIN
    EXECUTE IMMEDIATE 'ALTER PROFILE ${PROFILE_NAME} LIMIT password_rollover_time 0.05 idle_time 30';
    IF ${PROFILE_IDLE_TIME} > 0
    THEN
       EXECUTE IMMEDIATE 'ALTER PROFILE ${PROFILE_NAME} LIMIT idle_time ${IDLE_TIME}';
    END IF;
END;
/
exit;
EOSQL
