#!/bin/bash

# Update the default tape device to use if not explicitly set

. ~/.bash_profile

rman target / <<EORMAN
CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS  'SBT_LIBRARY=${ORACLE_HOME}/lib/libosbws.so, ENV=(OSB_WS_PFILE=${ORACLE_HOME}/dbs/osbws.ora)';
exit;
EORMAN