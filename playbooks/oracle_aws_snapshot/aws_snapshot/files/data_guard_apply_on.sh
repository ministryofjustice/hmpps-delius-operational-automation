#!/bin/bash
# Switch On Apply

. ~/.bash_profile

dgmgrl <<EODG
connect /
edit database ${ORACLE_SID} set state = 'APPLY-ON';
exit
EODG