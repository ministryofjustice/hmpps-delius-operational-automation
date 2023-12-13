#!/bin/bash
# Get Data Guard Apply Mode

. ~/.bash_profile

dgmgrl <<EODG | awk '/Intended State:/{print $3}'
connect /
show database ${ORACLE_SID};
exit
EODG