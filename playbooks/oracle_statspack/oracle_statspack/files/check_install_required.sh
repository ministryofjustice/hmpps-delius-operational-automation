#!/bin/bash
#
#  Statspack should be installed if no Control Management Packs are licenced
#  and the PERFSTAT User does not already exist.
#

. ~/.bash_profile

sqlplus -s /  as sysdba <<EOF
SET LINES 1000
SET PAGES 0
SET FEEDBACK OFF
SET HEADING OFF
WHENEVER SQLERROR EXIT FAILURE
SELECT      'YES' install_required
FROM        v\$database d
INNER JOIN  v\$parameter p
ON          p.name='control_management_pack_access'
AND         p.value='NONE'
INNER JOIN  v\$instance i
ON          i.instance_role = 'PRIMARY_INSTANCE'
LEFT JOIN   dba_users u
ON          u.username = 'PERFSTAT'
WHERE       u.username IS NULL;
EXIT
EOF
