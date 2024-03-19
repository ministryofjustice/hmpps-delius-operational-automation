#!/bin/bash 
 
. ~/.bash_profile

sqlplus -s / as sysdba << EOF

WHENEVER SQLERROR EXIT FAILURE
SET FEEDBACK OFF
SET HEADING OFF
SET PAGES 0

 SELECT
   CASE
   WHEN i.status != 'OPEN' THEN 'NOT OPEN'
   ELSE p.value
   END control_management_pack_access
 FROM v\$instance i
 CROSS JOIN v\$parameter p
 WHERE p.name = 'control_management_pack_access'

EOF