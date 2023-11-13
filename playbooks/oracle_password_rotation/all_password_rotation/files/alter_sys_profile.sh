#!/bin/bash
#
#  SYS_PROFILE is based on ORA_STIG_PROFILE
#  (Oracle Security Technical Implementation Guidelines compliance)
#
#

. ~/.bash_profile

[[ ! -z ${DB_NAME} ]] && CONNECT="@${DB_NAME}"
[[ -z ${LOGIN_USER} ]] && SYSDBA="as sysdba"

sqlplus -S /nolog <<EOSQL
connect ${LOGIN_USER}/${LOGIN_PWD}${CONNECT} ${SYSDBA}
set trimspool on
set pages 0
set lines 30
set feedback off
BEGIN
    -- Allow up to UNLIMITED failed login attempts to prevent lock-out on ADG
    -- (This appears to get locked after a random arbitrary number of failed login attempts
    --  regardless of any numeric limit set on FAILED_LOGIN_ATTEMPTS)
    EXECUTE IMMEDIATE 'ALTER PROFILE sys_profile LIMIT failed_login_attempts UNLIMITED';
    -- See: Sys Password Reset Is Not Reflecting In Sys.user$ PASSWORD_CHANGE_DATE (Doc ID 2482400.1)
    -- This means that the password is immediately placed in Grace time as soon as it is changed.
    -- We have to set _enable_ptime_update_for_sys=true and bounce the database for fix (included in 19.6)
    -- In the meantime just use a long life time
    EXECUTE IMMEDIATE 'ALTER PROFILE sys_profile LIMIT password_life_time 3650';
    -- If the account becomes locked in ADG then it can only be unlocked by reducing the PASSWORD_LOCK_TIME
    -- of the profile on the Primary (or by bouncing the Standby database).   However, this will not work
    -- if the PASSW_LOCK_UNLIM flag is set, which would happen with an unlimited lock-out.   Therefore
    -- we reduce the lock-out time from unlimited to one year so that this flag is not set.
    EXECUTE IMMEDIATE 'ALTER PROFILE sys_profile LIMIT password_lock_time 365';
END;
/
exit;
EOSQL
