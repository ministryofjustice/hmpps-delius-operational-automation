#!/bin/bash

. ~/.bash_profile

PARTITION_NAME=${1:?Usage: exchange_partition.sh <partition_name> <compress_for> <schema_name> <table_name>}
COMPRESS_FOR=${2:?Usage: exchange_partition.sh <partition_name> <compress_for> <schema_name> <table_name>}
SCHEMA_NAME=${3:?Usage: exchange_partition.sh <partition_name> <compress_for> <schema_name> <table_name>}
TABLE_NAME=${4:?Usage: exchange_partition.sh <partition_name> <compress_for> <schema_name> <table_name>}

sqlplus -s /nolog <<EOSQL
connect / as sysdba

WHENEVER SQLERROR EXIT FAILURE

SET SERVEROUT ON
DECLARE
    l_partition_name VARCHAR2(128) := '${PARTITION_NAME}';
    l_schema_name           VARCHAR2(128) := '${SCHEMA_NAME}';
    l_table_name            VARCHAR2(128) := '${TABLE_NAME}';
    l_compress_for          VARCHAR2(30)  := '${COMPRESS_FOR}';
    l_rows_kept             NUMBER;
    l_rows_before           NUMBER;
    l_business_interaction_id delius_app_schema.business_interaction.business_interaction_id%TYPE;
    l_partition_bytes_before NUMBER;
    l_partition_bytes_after  NUMBER;
BEGIN

    -- Get the ID for the GET_EXTRACT_DATA business interaction type
    SELECT business_interaction_id
    INTO   l_business_interaction_id
    FROM   ${SCHEMA_NAME}.business_interaction
    WHERE  UPPER(description) = 'GET_EXTRACTS_DATA';

    DBMS_APPLICATION_INFO.SET_MODULE(
        module_name => 'exchange_partition',
        action_name => 'Initializing: ' || l_partition_name
    );

    DBMS_APPLICATION_INFO.SET_ACTION(action_name => 'Creating exchange table');

    -- Record partition size before exchange
    SELECT NVL(SUM(bytes), 0)
    INTO   l_partition_bytes_before
    FROM   dba_segments
    WHERE  owner          = l_schema_name
    AND    segment_name   = l_table_name
    AND    partition_name = l_partition_name;

    -- Record row count before exchange
    EXECUTE IMMEDIATE
        'SELECT COUNT(*) FROM ' || l_schema_name || '.' || l_table_name || ' PARTITION (' || l_partition_name || ')'
    INTO l_rows_before;

    -- Drop staging table if it exists from a previous failed run
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE ' || l_schema_name || '.z_' || l_table_name || '_xchg PURGE';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE != -942 THEN RAISE; END IF; -- -942 = table or view does not exist
    END;

    -- Create exchange table with matching structure and storage properties
    -- FOR EXCHANGE WITH TABLE (Oracle 12c+) ensures full compatibility for partition exchange
    EXECUTE IMMEDIATE
        'CREATE TABLE ' || l_schema_name || '.z_' || l_table_name || '_xchg ' ||
        'FOR EXCHANGE WITH TABLE ' || l_schema_name || '.' || l_table_name;

    -- Restore the partition's original compression before inserting so that
    -- the incoming data is stored in the same format as the source partition.
    -- FOR EXCHANGE inherits the table default, which may differ from the partition.
    IF l_compress_for != 'NONE' THEN
        EXECUTE IMMEDIATE
            'ALTER TABLE ' || l_schema_name || '.z_' || l_table_name || '_xchg ' ||
            'COMPRESS ' || l_compress_for;
    END IF;

    -- PCTFREE=0: the exchange table is write-once (no subsequent UPDATEs),
    -- so no free space needs to be reserved in each block.
    EXECUTE IMMEDIATE
        'ALTER TABLE ' || l_schema_name || '.z_' || l_table_name || '_xchg PCTFREE 0';

    DBMS_APPLICATION_INFO.SET_ACTION(action_name => 'Populating exchange table');

    -- Populate staging table with all rows except BUSINESS_INTERACTION_ID = l_business_interaction_id
    EXECUTE IMMEDIATE
        'INSERT /*+ APPEND */ INTO ' || l_schema_name || '.z_' || l_table_name || '_xchg ' ||
        'SELECT * FROM ' || l_schema_name || '.' || l_table_name || ' PARTITION (' || l_partition_name || ') ' ||
        'WHERE business_interaction_id != ' || l_business_interaction_id;

    l_rows_kept := SQL%ROWCOUNT;
    COMMIT;

    DBMS_APPLICATION_INFO.SET_ACTION(action_name => 'Exchanging partition');

    -- Exchange the partition with the staging table.
    -- After the exchange:
    --   the partition holds only the rows kept in the staging table (BID != l_business_interaction_id)
    --   z_<table>_xchg holds the original partition rows (including BID = l_business_interaction_id)
    -- WITHOUT VALIDATION is safe here because all retained rows were already in
    -- this partition and therefore already satisfy its key bounds.
    EXECUTE IMMEDIATE
        'ALTER TABLE ' || l_schema_name || '.' || l_table_name || ' ' ||
        'EXCHANGE PARTITION ' || l_partition_name || ' ' ||
        'WITH TABLE ' || l_schema_name || '.z_' || l_table_name || '_xchg ' ||
        'WITHOUT VALIDATION';

    DBMS_APPLICATION_INFO.SET_ACTION(action_name => 'Dropping exchange table');

    -- Record partition size after exchange (before dropping the exchange table)
    SELECT NVL(SUM(bytes), 0)
    INTO   l_partition_bytes_after
    FROM   dba_segments
    WHERE  owner          = l_schema_name
    AND    segment_name   = l_table_name
    AND    partition_name = l_partition_name;

    -- Drop the staging table (now contains rows to be removed)
    EXECUTE IMMEDIATE 'DROP TABLE ' || l_schema_name || '.z_' || l_table_name || '_xchg PURGE';

    DBMS_APPLICATION_INFO.SET_MODULE(module_name => NULL, action_name => NULL);

    DBMS_OUTPUT.PUT_LINE('EXCHANGE_PARTITION_STATUS=SUCCESS');
    DBMS_OUTPUT.PUT_LINE('EXCHANGE_PARTITION_NAME=' || l_partition_name);
    DBMS_OUTPUT.PUT_LINE('EXCHANGE_PARTITION_ROWS_BEFORE=' || l_rows_before);
    DBMS_OUTPUT.PUT_LINE('EXCHANGE_PARTITION_ROWS_AFTER=' || l_rows_kept);
    DBMS_OUTPUT.PUT_LINE('EXCHANGE_PARTITION_ROWS_REMOVED=' || (l_rows_before - l_rows_kept));
    DBMS_OUTPUT.PUT_LINE('EXCHANGE_PARTITION_BYTES_BEFORE=' || l_partition_bytes_before);
    DBMS_OUTPUT.PUT_LINE('EXCHANGE_PARTITION_BYTES_AFTER=' || l_partition_bytes_after);
    DBMS_OUTPUT.PUT_LINE('EXCHANGE_PARTITION_BYTES_REDUCTION=' || (l_partition_bytes_before - l_partition_bytes_after));

EXCEPTION
    WHEN OTHERS THEN
        DBMS_APPLICATION_INFO.SET_MODULE(module_name => NULL, action_name => NULL);
        DBMS_OUTPUT.PUT_LINE('EXCHANGE_PARTITION_STATUS=FAILED');
        DBMS_OUTPUT.PUT_LINE('EXCHANGE_PARTITION_ERROR=' || SQLERRM);
        BEGIN
            EXECUTE IMMEDIATE 'DROP TABLE ' || l_schema_name || '.z_' || l_table_name || '_xchg PURGE';
        EXCEPTION
            WHEN OTHERS THEN NULL;
        END;
        RAISE;
END;
/

EXIT
EOSQL
