#!/bin/bash
#
#  Get the management pack parameter to see which packs are available
#

. ~/.bash_profile

sqlplus -s / as sysdba << EOF

SET HEADING OFF
SET PAGES 0
WHENEVER SQLERROR EXIT FAILURE;

SELECT value
FROM   v\$parameter
WHERE  name = 'control_management_pack_access';
    
EXIT
EOF