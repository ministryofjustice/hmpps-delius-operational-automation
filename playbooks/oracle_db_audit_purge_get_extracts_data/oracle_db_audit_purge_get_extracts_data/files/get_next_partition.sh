#!/bin/bash

. ~/.bash_profile

# USE_PARALLEL=1 enables parallel query (recommended when running on ADG standby)
USE_PARALLEL=${1:-0}

sqlplus -s /nolog <<EOSQL
connect / as sysdba

SET SERVEROUT ON
DECLARE
    l_business_interaction_id delius_app_schema.business_interaction.business_interaction_id%TYPE;
    l_dummy               NUMBER;
    l_high_value_raw      VARCHAR2(255);
    l_high_value          DATE;
    l_compress_for        VARCHAR2(30);
    l_partition_count     NUMBER;
    l_partition_num  NUMBER := 0;
    l_rindex         BINARY_INTEGER := DBMS_APPLICATION_INFO.set_session_longops_nohint;
    l_slno           BINARY_INTEGER;
BEGIN

    DBMS_APPLICATION_INFO.SET_MODULE(
        module_name => 'get_next_partition',
        action_name => 'Initializing'
    );

    -- Enable parallel query when running on ADG standby for better performance.
    -- Omitting PARALLEL <n> lets Oracle use PARALLEL_THREADS_PER_CPU * CPU_COUNT.
    IF '${USE_PARALLEL}' = '1' THEN
        EXECUTE IMMEDIATE 'ALTER SESSION FORCE PARALLEL QUERY';
    END IF;

    -- Count partitions to support progress reporting
    SELECT COUNT(*)
    INTO   l_partition_count
    FROM   all_tab_partitions
    WHERE  table_name  = 'AUDITED_INTERACTION'
    AND    table_owner = 'DELIUS_APP_SCHEMA';

    -- Get the ID for the GET_EXTRACT_DATA business interaction type
    SELECT business_interaction_id
    INTO   l_business_interaction_id
    FROM   delius_app_schema.business_interaction
    WHERE  UPPER(description) = 'GET_EXTRACTS_DATA';

    FOR p IN (
        SELECT partition_name
        FROM   all_tab_partitions
        WHERE  table_name = 'AUDITED_INTERACTION'
        AND    table_owner = 'DELIUS_APP_SCHEMA'
        ORDER BY partition_position
    )
    LOOP
        l_partition_num := l_partition_num + 1;

        -- Fetch HIGH_VALUE (LONG -> VARCHAR2 implicit conversion in PL/SQL SELECT INTO)
        -- and COMPRESS_FOR for the partition compression type
        SELECT high_value, compress_for
        INTO   l_high_value_raw, l_compress_for
        FROM   all_tab_partitions
        WHERE  table_name      = 'AUDITED_INTERACTION'
        AND    table_owner     = 'DELIUS_APP_SCHEMA'
        AND    partition_name  = p.partition_name;

        -- Extract the date portion from the HIGH_VALUE string
        -- e.g. TIMESTAMP' 2024-03-01 00:00:00' -> 2024-03-01
        l_high_value := TO_DATE(
            REGEXP_SUBSTR(l_high_value_raw, '\d{4}-\d{2}-\d{2}'),
            'YYYY-MM-DD'
        );

        CONTINUE WHEN l_high_value < DATE '2015-01-01';

        DBMS_APPLICATION_INFO.SET_ACTION(
            action_name => l_partition_num || '/' || l_partition_count ||
                           ' ' || p.partition_name || ' (' || TO_CHAR(l_high_value, 'YYYY-MM-DD') || ')'
        );

        DBMS_APPLICATION_INFO.SET_SESSION_LONGOPS(
            rindex      => l_rindex,
            slno        => l_slno,
            op_name     => 'get_next_partition',
            target_desc => 'DELIUS_APP_SCHEMA.AUDITED_INTERACTION',
            sofar       => l_partition_num,
            totalwork   => l_partition_count,
            units       => 'partitions'
        );

        BEGIN
            EXECUTE IMMEDIATE
                'SELECT 1 ' ||
                'FROM DELIUS_APP_SCHEMA.AUDITED_INTERACTION PARTITION (' || p.partition_name || ') ' ||
                'WHERE BUSINESS_INTERACTION_ID = :1 AND ROWNUM = 1'
            INTO l_dummy
            USING l_business_interaction_id;

            DBMS_APPLICATION_INFO.SET_MODULE(
                module_name => NULL,
                action_name => NULL
            );
            DBMS_OUTPUT.PUT_LINE('NEXT_PARTITION_ID=' || p.partition_name);
            DBMS_OUTPUT.PUT_LINE('NEXT_PARTITION_HIGH_VALUE=' || TO_CHAR(l_high_value, 'YYYY-MM-DD'));
            DBMS_OUTPUT.PUT_LINE('NEXT_PARTITION_COMPRESS_FOR=' || NVL(l_compress_for, 'NONE'));
            RETURN;

        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                NULL; -- try next partition
        END;
    END LOOP;

    DBMS_APPLICATION_INFO.SET_MODULE(
        module_name => NULL,
        action_name => NULL
    );
    DBMS_OUTPUT.PUT_LINE(
        'No partitions contain GET_EXTRACTS_DATA'
    );
END;
/

EXIT
EOSQL