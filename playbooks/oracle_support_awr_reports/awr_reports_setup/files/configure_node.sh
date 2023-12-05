#!/bin/bash

. ~/.bash_profile

sqlplus -s / as sysdba << EOF

SET LINES 132
SET PAGES 0
SET FEEDBACK OFF
SET HEADING OFF
WHENEVER SQLERROR EXIT FAILURE;

DECLARE

l_node_name_local   VARCHAR2(30);

BEGIN

    SELECT dbms_umf.get_node_name_local 
    INTO l_node_name_local
    FROM dual;

EXCEPTION WHEN OTHERS
THEN
    dbms_umf.configure_node ('${NODE}','${DB_LINK}');
END;
/

EXIT
EOF