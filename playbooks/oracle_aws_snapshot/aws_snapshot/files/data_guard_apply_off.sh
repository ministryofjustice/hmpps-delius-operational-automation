#!/bin/bash
# Switch Off Apply

. ~/.bash_profile

dgmgrl <<EODG
connect /
edit database ${ORACLE_SID} set state = 'APPLY-OFF';
exit
EODG