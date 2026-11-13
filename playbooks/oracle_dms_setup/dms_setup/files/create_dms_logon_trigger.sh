#!/bin/bash
#
#  We wish to block any attempts to use the DMS System acount for adhoc user access
#  Therefore restrict the access to known DMS OSUSER and PROGRAM values

. ~/.bash_profile

# The following trigger prevents access to the dms_user schema except by well
# known program and OS user names for the AWS DMS agent.   To avoid the trigger
# being by-passed, it must be created in a different schema to the dms_user
# itself.  We therefore use the already existing {{ user_support_user }} schema.
#
# We only allow the DMS user to connect to the ADG standby database, unless it is
# connecting over the mandatory database link AWSDMS_DBLINK, or if there
# is no standby database available.
#
# We also allow access to the primary if the DMS Task must write data.
#  (*)  For Analytics Platform - this is read only
#  (*)  For Audited Interaction Preservation - this writes user data
#
sqlplus -s / as sysdba << EOF

WHENEVER SQLERROR EXIT FAILURE;

GRANT SELECT ON v_\$database to ${USER_SUPPORT_USER};

CREATE OR REPLACE TRIGGER ${USER_SUPPORT_USER}.${DMS_USER}_restrict
AFTER LOGON ON ${DMS_USER}.SCHEMA
DECLARE
   l_database_role           v\$database.database_role%TYPE;
   l_standby_only            BOOLEAN := ${STANDBY_ONLY};
   l_set_nls_date_format     BOOLEAN := ${SET_NLS_DATE_FORMAT};
BEGIN
    -- We allow access to the primary database via a database link only
    IF SYS_CONTEXT('USERENV','DBLINK_INFO') LIKE '%DBLINK_NAME=AWSDMS_DBLINK%'
    THEN 
        NULL;
    ELSE
        -- Otherwise we only allow access to an ADG standby using the
        -- expected client program and OS account for either
        -- (1) AWS DMS Replication Agent, or
        -- (2) ORACLE SCHEDULER
        IF  NOT (SYS_CONTEXT('USERENV','CLIENT_PROGRAM_NAME') LIKE 'repctl%' AND SYS_CONTEXT('USERENV','OS_USER') = 'rdsdb')
        AND NOT (SYS_CONTEXT('USERENV','CLIENT_PROGRAM_NAME') LIKE 'oracle%(J%' AND SYS_CONTEXT('USERENV','OS_USER') = 'oracle')
        AND NOT (SYS_CONTEXT('USERENV','CLIENT_PROGRAM_NAME') LIKE 'DataMigEndpointDriverService%' AND SYS_CONTEXT('USERENV','OS_USER') = 'eds')        
        THEN
            RAISE_APPLICATION_ERROR(-20921,'This account is for use by the AWS DMS Agent only - not '||SYS_CONTEXT('USERENV','CLIENT_PROGRAM_NAME')||' by '||SYS_CONTEXT('USERENV','OS_USER'));
        END IF;
        SELECT database_role
        INTO   l_database_role
        FROM   v\$database;
        IF l_database_role = 'PRIMARY' AND l_standby_only
        THEN
            RAISE_APPLICATION_ERROR(-20922,'This account is for use with ADG Standby only.');
        END IF;
        IF l_set_nls_date_format
        THEN
           EXECUTE IMMEDIATE 'ALTER SESSION SET nls_date_format = ''YYYY-MM-DD HH24:MI:SS''';
        END IF;
    END IF;
END;
/

EXIT
EOF