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
    FROM dba_umf_service
    WHERE topology_name = 'AWR';

    IF l_count = 0
    THEN
        DBMS_WORKLOAD_REPOSITORY.register_remote_database(node_name=>'${ADG_NODE}',topology_name => '${TOPOLOGY_NAME}');
    END IF;

END;
/

EXIT
EOF