#!/bin/bash

. ~/.bash_profile

sqlplus -s / as sysdba <<EOF
SET LINES 1000
SET PAGES 0
SET FEEDBACK OFF
SET HEADING OFF
WHENEVER SQLERROR EXIT FAILURE
SELECT   name||':'||scn 
FROM     v\$restore_point
WHERE    database_incarnation# = (SELECT last_open_incarnation#
                                  FROM v\$database)
ORDER BY scn;
EXIT
EOF