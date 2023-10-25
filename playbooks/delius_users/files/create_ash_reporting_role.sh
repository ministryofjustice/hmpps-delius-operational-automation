#!/bin/bash
#
#  The ASH Reporting role is only created if the DIAGNOSTICS pack if enabled
#

. ~/.bash_profile

sqlplus -s / as sysdba << EOF

WHENEVER SQLERROR EXIT FAILURE;

BEGIN
    FOR check_not_exists IN (SELECT 1
                                FROM   dba_roles
                                WHERE  role = 'DELIUS_ASH_ROLE'
                                HAVING COUNT(*) = 0)
    LOOP
        EXECUTE IMMEDIATE 'CREATE ROLE delius_ash_role';
    END LOOP;
END;
/

GRANT select_catalog_role TO delius_ash_role;

EXIT
EOF