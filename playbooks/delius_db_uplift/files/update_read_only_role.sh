#!/bin/bash

# Add any newly created tables to the Read Only Role
# We grant read on any new tables or view where the required grants do not already exist
# (Note: we do no issue grants in databases where the DELIUS_READ_ONLY_ROLE does not exist)

. ~/.bash_profile

sqlplus -s / as sysdba <<EOSQL
SET SERVEROUT ON
WHENEVER SQLERROR EXIT FAILURE;
SET FEEDBACK OFF
SET PAGES 0
DECLARE
   l_counter INTEGER := 0;
BEGIN
    FOR x IN (
        SELECT
            t.owner,
            (
                CASE
                    WHEN t.iot_type = 'IOT_OVERFLOW' THEN
                        t.iot_name
                    ELSE
                        t.table_name
                END
            ) table_name
        FROM
            dba_tables t
            CROSS JOIN dba_roles r
        WHERE
            t.owner IN ( 'DELIUS_APP_SCHEMA', 'DELIUS_CFO' )
            AND t.table_name NOT LIKE 'AQ$_%'
            AND r.role = 'DELIUS_READ_ONLY_ROLE'
        UNION ALL
        SELECT
            v.owner,
            v.view_name table_name
        FROM
            dba_views v
            CROSS JOIN dba_roles r
        WHERE
            v.owner IN ( 'DELIUS_APP_SCHEMA', 'DELIUS_CFO' )
            AND v.view_name NOT LIKE 'AQ$_%'
            AND r.role = 'DELIUS_READ_ONLY_ROLE'
        MINUS
        SELECT
            tp.owner,
            tp.table_name
        FROM
            dba_tab_privs tp
        WHERE
                tp.grantee = 'DELIUS_READ_ONLY_ROLE'
            AND tp.privilege = 'READ'
    ) LOOP
        EXECUTE IMMEDIATE 'GRANT READ ON '
                          || x.owner
                          || '.'
                          || x.table_name
                          || ' TO delius_read_only_role';
        l_counter := l_counter + 1;
    END LOOP;
    DBMS_OUTPUT.put_line(l_counter);
END;
/
EOSQL

