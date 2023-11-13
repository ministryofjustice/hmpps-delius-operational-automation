#!/bin/bash
#  Check that SYS Password works for remote connection

. ~/.bash_profile

[[ "${DB_NAME}" == "NONE" ]] && exit 0

EXITCODE=$(sqlplus -S /nolog <<EOSQL
connect sys/${SYS_PASSWORD}@${DB_NAME} as sysdba
exit
EOSQL
)

echo $EXITCODE
