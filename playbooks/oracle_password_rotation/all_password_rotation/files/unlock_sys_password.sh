#!/bin/bash
#
#  Unlock SYS Password on All Databases (Timed Lock)
#  
#  Running ACCOUNT UNLOCK for SYS either on Primary or Standby has been found
#  to fail to resolve ORA-28000 on ADG Standby databases.    As a workaround
#  we temporarily move SYS to a different profile which has a short unlock
#  period and wait for it do become unlocked automatically.
#
#  No MOS Note or Documentation has so far been found to explain this behaviour.
#
#

. ~/.bash_profile

sqlplus -S /nolog <<EOSQL
connect / as sysdba
set trimspool on
set pages 0
set lines 200
whenever sqlerror continue

-- Ensure SYS is unlocked
ALTER USER sys ACCOUNT UNLOCK;

-- Create temporary profile for the unlock of SYS -- this will
-- contain all existing limits but will have the shortest
-- possible automatic unlock time.
-- (This should NOT be based on the DEFAULT profile as it may
--  be in use long enough that the SYS account gets locked out)
DECLARE
    l_exists  INTEGER;
    l_command VARCHAR2(1000);
BEGIN
    SELECT COUNT(*)
    INTO   l_exists
    FROM   dba_profiles
    WHERE  profile = 'UNLOCK_SYS_ONLY';
    IF l_exists > 0 THEN
       EXECUTE IMMEDIATE 'DROP PROFILE unlock_sys_only';
    END IF;
    SELECT
        'CREATE PROFILE unlock_sys_only LIMIT '
        || LISTAGG(resource_name
                   || ' '
                   || limit, ' ')
    INTO l_command
    FROM
        dba_profiles
    WHERE
        profile = (SELECT profile
                   FROM   dba_users
                   WHERE  username = 'SYS');
    EXECUTE IMMEDIATE l_command;
END;
/

-- Alter temporary profile with shortest possible lock time (0.0001 days = 83 seconds)
ALTER PROFILE unlock_sys_only LIMIT PASSWORD_LOCK_TIME 0.0001;


COLUMN profile NEW_VALUE ORIGINAL_PROFILE

SELECT profile
FROM   dba_users
WHERE  username = 'SYS';

ALTER USER sys PROFILE unlock_sys_only;

-- Wait for the password to automatically unlock
BEGIN
   -- Wait for 0.0001 days = 83 seconds
   DBMS_SESSION.sleep(83);
END;
/

BEGIN
   -- Wait a big longer for a safety margin
   DBMS_SESSION.sleep(20);
END;
/

-- Revert SYS back to its normal profile
ALTER USER sys PROFILE &&ORIGINAL_PROFILE;

-- Get rid of temporary profile
-- DROP PROFILE unlock_sys_only;

exit;
EOSQL
