#!/bin/bash

. ~/.bash_profile

sqlplus -s /  as sysdba <<EOF
WHENEVER SQLERROR EXIT FAILURE;
SET LINES 1000
SET PAGES 0
SET HEADING OFF
SET FEEDBACK OFF
SELECT     SYS_CONTEXT('userenv','instance_name')||': '||LISTAGG(rp.name||' ('||TO_CHAR(rp.time,'DD-MON-YYYY HH24:MI')||')',',')
            WITHIN GROUP (ORDER BY rp.time)
FROM       v\$restore_point rp;
EXIT;
EOF
