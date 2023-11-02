#!/bin/bash

. ~/.bash_profile

sqlplus -s /  as sysdba <<EOF
WHENEVER SQLERROR EXIT FAILURE;
SET FEEDBACK OFF
SET HEADING OFF

SELECT CASE COUNT(*)
       WHEN 0 THEN 'NO'
       ELSE 'YES'
       END
FROM   V\$RESTORE_POINT 
WHERE  name       = '${RESTORE_POINT_NAME}' 
AND    replicated = 'YES';

EXIT;
EOF