#!/bin/bash 

. ~/.bash_profile

sqlplus -s / as sysdba << EOF

WHENEVER SQLERROR EXIT FAILURE
SET FEEDBACK OFF
SET HEADING OFF
SET PAGES 0

DEFINE dbid=${DBID}
DEFINE num_days=''
DEFINE begin_snap=${BEGIN_SNAP}
DEFINE end_snap=${END_SNAP}
DEFINE directory_name=${DIRECTORY_NAME}
DEFINE file_name=${FILE_NAME}

@?/rdbms/admin/awrextr.sql

EOF