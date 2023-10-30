#!/bin/bash

export ORACLE_SID=$1
export RESTORE_DATETIME=$2

export PATH=$PATH:/usr/local/bin;
export ORAENV_ASK=NO ;
. oraenv >/dev/null;

# Get scn greater or equal to the restore datetime
sqlplus -s "/ as sysdba" <<EOF
whenever sqlerror exit 1
set feedback off heading off verify off echo off pages 0
select ltrim(next_change#)
from v\$archived_log
where to_date('${RESTORE_DATETIME}','DD-MM-YYYY HH24:MI:SS')
between first_time and next_time;
EOF
