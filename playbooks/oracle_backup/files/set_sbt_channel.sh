#!/bin/bash

export ORACLE_SID=$1
export PATH=$PATH:/usr/local/bin;
export ORAENV_ASK=NO ;
. oraenv >/dev/null;

rman target / <<EOF
CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=${ORACLE_HOME}/lib/libosbws.so, ENV=(OSB_WS_PFILE=${ORACLE_HOME}/dbs/osbws.ora)';
EOF
