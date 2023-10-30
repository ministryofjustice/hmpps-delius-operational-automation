#!/bin/bash

export ORACLE_SID=$1
export CATALOG=$2

export PATH=$PATH:/usr/local/bin;
export ORAENV_ASK=NO ;
. oraenv >/dev/null;

tnsping ${CATALOG} | grep Attempting | sed 's/Attempting to contact //' | sed 's/ //g'
