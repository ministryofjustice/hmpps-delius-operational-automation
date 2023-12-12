#!/bin/bash

. ~/.bash_profile

sqlplus -s / as sysdba << EOF
WHENEVER SQLERROR EXIT FAILURE;
ALTER SYSTEM FLUSH SHARED_POOL;
EXIT
EOF