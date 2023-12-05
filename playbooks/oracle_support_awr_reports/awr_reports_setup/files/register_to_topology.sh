#!/bin/bash

. ~/.bash_profile

sqlplus -s / as sysdba << EOF

SET LINES 132
SET PAGES 0
SET FEEDBACK OFF
SET HEADING OFF
WHENEVER SQLERROR EXIT FAILURE;

DECLARE

l_count     NUMBER(1);

BEGIN

    SELECT COUNT(*) 
    INTO l_count
    FROM dba_umf_registration
    WHERE topology_name = '${TOPOLOGY_NAME}'
    AND node_name = '${ADG_NODE}';

    IF l_count = 0
    THEN
        DBMS_UMF.register_node ('${TOPOLOGY_NAME}', '${ADG_NODE}', '${PRIMARY_DB_LINK}', '${ADG_DB_LINK}', 'FALSE', 'FALSE');
    END IF;

END;
/

EXIT
EOF