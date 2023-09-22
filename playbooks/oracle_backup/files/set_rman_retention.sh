#!/bin/bash

export ORACLE_SID=$1
export RETENTION_POLICY=$2

export PATH=$PATH:/usr/local/bin;
export ORAENV_ASK=NO ;
. oraenv >/dev/null;

rman target / <<EOF
configure retention policy to ${RETENTION_POLICY};
EOF
