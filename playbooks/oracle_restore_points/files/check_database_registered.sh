#!/bin/bash

. ~/.bash_profile

NAME=${1}
CONNECT_CATALOG=${2}

sqlplus -s ${CONNECT_CATALOG}<<EOF
WHENEVER SQLERROR EXIT FAILURE;
SET PAGES 0
SET FEEDBACK OFF
SET HEADING OFF
SET SERVEROUT ON

SELECT LTRIM(COUNT(*))
FROM rc_database
WHERE name = UPPER('${NAME}');

EOF

# If the above fails with an error, do not fail the script
# but simply return a 0 to indicate that the database is not registered
[[ $? -gt 0 ]] && echo 0

exit 0