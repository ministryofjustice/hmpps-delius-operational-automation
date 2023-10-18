#!/bin/bash
#
#  Check if the Master PDT Semaphore is set to STOP
# 

. ~/.bash_profile

sqlplus -s / as sysdba <<EOSQL
SET FEEDBACK OFF
SET HEADING OFF
WHENEVER SQLERROR EXIT FAILURE
WITH
    FUNCTION get_gc_master_component_id RETURN INTEGER AS
        l_val INTEGER;
    BEGIN
        l_val := delius_app_schema.pkg_perf_collector.gc_master_component_id;
        RETURN l_val;
    END;
SELECT
    COALESCE(MAX(signal), 'NOT_STOPPED') signal
FROM
    delius_app_schema.pdt_semaphore
WHERE
    component_code = get_gc_master_component_id;
/
EXIT
EOSQL