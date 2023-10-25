#!/bin/bash
#
#  Any user with the suffix _SRO is a Standby Datbase Only Read-Only user
#  and should not be allowed to connect to the primary database.   This is
#  enforced by the following trigger.   To avoid it being by-passed this
#  trigger is created in the DELIUS_SUPPORT_USER account.   One trigger is
#  created for each _SRO account, to avoid it being fired for any other
#  accounts.

. ~/.bash_profile

sqlplus -s / as sysdba << EOF

WHENEVER SQLERROR EXIT FAILURE;

GRANT SELECT ON v_\$database to delius_user_support;

CREATE OR REPLACE TRIGGER delius_user_support.${STANDBY_RO_USER}
AFTER LOGON ON ${STANDBY_RO_USER}.SCHEMA
DECLARE
   l_database_role v\$database.database_role%TYPE;
BEGIN
    SELECT database_role
    INTO   l_database_role
    FROM   v\$database;
    IF l_database_role = 'PRIMARY'
    THEN
        RAISE_APPLICATION_ERROR(-20923,'The ${STANDBY_RO_USER} account is for use with ADG Standby only.');
    END IF;
END;
/

EXIT
EOF