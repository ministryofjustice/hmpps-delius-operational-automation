#!/bin/bash

. ~/.bash_profile

HIGH_VALUE_DATE=${1:?Usage: get_partition_for_high_value.sh <high_value_date YYYY-MM-DD> <schema_name>}
SCHEMA_NAME=${2:?Usage: get_partition_for_high_value.sh <high_value_date YYYY-MM-DD> <schema_name>}

sqlplus -s /nolog <<EOSQL
connect / as sysdba

SET SERVEROUT ON
DECLARE
    l_target_date  DATE          := TO_DATE('${HIGH_VALUE_DATE}', 'YYYY-MM-DD');
    l_schema_name  VARCHAR2(128) := UPPER('${SCHEMA_NAME}');
    l_high_value   VARCHAR2(255);
    l_high_value_date DATE;
BEGIN

    DBMS_APPLICATION_INFO.SET_MODULE(
        module_name => 'get_partition_for_high_value',
        action_name => 'Searching: ' || '${HIGH_VALUE_DATE}'
    );

    FOR p IN (
        SELECT partition_name
        FROM   all_tab_partitions
        WHERE  table_name  = 'AUDITED_INTERACTION'
        AND    table_owner = l_schema_name
        ORDER BY partition_position
    )
    LOOP
        -- Fetch HIGH_VALUE (LONG -> VARCHAR2 implicit conversion in PL/SQL SELECT INTO)
        SELECT high_value
        INTO   l_high_value
        FROM   all_tab_partitions
        WHERE  table_name     = 'AUDITED_INTERACTION'
        AND    table_owner    = l_schema_name
        AND    partition_name = p.partition_name;

        l_high_value_date := TO_DATE(
            REGEXP_SUBSTR(l_high_value, '\d{4}-\d{2}-\d{2}'),
            'YYYY-MM-DD'
        );

        IF l_high_value_date = l_target_date THEN
            DBMS_APPLICATION_INFO.SET_MODULE(module_name => NULL, action_name => NULL);
            DBMS_OUTPUT.PUT_LINE('PARTITION_NAME=' || p.partition_name);
            RETURN;
        END IF;
    END LOOP;

    DBMS_APPLICATION_INFO.SET_MODULE(module_name => NULL, action_name => NULL);
    DBMS_OUTPUT.PUT_LINE('PARTITION_NAME=');
    DBMS_OUTPUT.PUT_LINE('PARTITION_NOT_FOUND=No partition has HIGH_VALUE ' || '${HIGH_VALUE_DATE}');

END;
/

EXIT
EOSQL
