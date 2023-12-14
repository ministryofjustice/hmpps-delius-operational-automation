#!/bin/bash
#
#  SYS_PROFILE is based on ORA_STIG_PROFILE
#  (Oracle Security Technical Implementation Guidelines compliance)
#

. ~/.bash_profile

sqlplus -S / sysdba <<EOSQL
set trimspool on
set pages 0
set lines 30
set feedback off
DECLARE
    l_command VARCHAR2(1000);
BEGIN
    SELECT
        'CREATE PROFILE sys_profile LIMIT '
        || LISTAGG(resource_name
                   || ' '
                   || limit, ' ')
    INTO l_command
    FROM
        dba_profiles
    WHERE
            profile = 'ORA_STIG_PROFILE'
        AND limit != 'DEFAULT';

    EXECUTE IMMEDIATE l_command;
END;
/
exit;
EOSQL
