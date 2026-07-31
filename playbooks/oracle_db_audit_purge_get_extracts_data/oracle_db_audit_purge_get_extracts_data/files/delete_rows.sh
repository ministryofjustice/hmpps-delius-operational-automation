#!/bin/bash

# This script is only used for MIS data prior to January 2015 as before
# this date it does not use monthly partitioning as used by Delius.
# Fortunately the volumes of these really old partitions are low so we can
# just delete the data rather than using partition exchange.

. ~/.bash_profile

# HIGH_VALUE format is YYYY-MM-DD
HIGH_VALUE=${1:?Usage: exchange_partition.sh <high_value> <schema_name> <table_name>}
SCHEMA_NAME=${2:?Usage: exchange_partition.sh <high_value> <schema_name> <table_name>}
TABLE_NAME=${3:?Usage: exchange_partition.sh <high_value> <schema_name> <table_name>}

sqlplus -s /nolog <<EOSQL
connect / as sysdba

SET SERVEROUT ON
DECLARE
    l_high_value            VARCHAR2(30) :=  '${HIGH_VALUE}';
    l_schema_name           VARCHAR2(128) := '${SCHEMA_NAME}';
    l_table_name            VARCHAR2(128) := '${TABLE_NAME}';
    l_rows_deleted          NUMBER;
    l_business_interaction_id ${SCHEMA_NAME}.business_interaction.business_interaction_id%TYPE;
BEGIN

    -- Validate HIGH_VALUE format is YYYY-MM-DD
    IF NOT REGEXP_LIKE(l_high_value, '^\d{4}-\d{2}-\d{2}$') THEN
        RAISE_APPLICATION_ERROR(-20001, 'HIGH_VALUE must be in YYYY-MM-DD format, got: ' || l_high_value);
    END IF;

    -- Get the ID for the GET_EXTRACT_DATA business interaction type
    SELECT business_interaction_id
    INTO   l_business_interaction_id
    FROM   ${SCHEMA_NAME}.business_interaction
    WHERE  UPPER(description) = 'GET_EXTRACTS_DATA';

    DBMS_APPLICATION_INFO.SET_ACTION(action_name => 'Deleting rows before '||l_high_value);

    EXECUTE IMMEDIATE
        'DELETE FROM ' || l_schema_name || '.' || l_table_name || ' ' ||
        'WHERE date_time < DATE ''' || l_high_value || '''' ;

    l_rows_deleted := SQL%ROWCOUNT;

    DBMS_APPLICATION_INFO.SET_MODULE(module_name => NULL, action_name => NULL);

    DBMS_OUTPUT.PUT_LINE('ROWS_DELETED='||l_rows_deleted);
END;
/

EXIT
EOSQL
