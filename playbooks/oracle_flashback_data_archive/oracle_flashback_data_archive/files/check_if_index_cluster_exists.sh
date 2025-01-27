#!/bin/bash

. ~/.bash_profile

sqlplus -s /  as sysdba <<EOF
SET LINES 1000
SET PAGES 0
SET FEEDBACK OFF
SET HEADING OFF
WHENEVER SQLERROR EXIT FAILURE
select cluster_name 
from dba_tables 
where table_name = 'SMON_SCN_TIME';                    
EXIT
EOF
