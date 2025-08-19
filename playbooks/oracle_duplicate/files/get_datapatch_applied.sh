#!/bin/bash
# Check if Datapatch has been successfully applied for the current database version.

. ~/.bash_profile

sqlplus -s /nolog <<EOSQL
connect / as sysdba

WHENEVER SQLERROR EXIT FAILURE
SET FEEDBACK OFF
SET SERVEROUT ON
SET HEADING OFF
SET PAGES 0

SELECT
    CASE
        WHEN COUNT(*) = 0 THEN
            'Datapatch is not installed.'
        ELSE
            'Datapatch is installed.'
    END datapatch_status
FROM
    dba_registry_sqlpatch
WHERE
        target_version = (
            SELECT
                version_full
            FROM
                product_component_version
        )
    AND patch_type = 'RU'
    AND status = 'SUCCESS';

EXIT
EOSQL