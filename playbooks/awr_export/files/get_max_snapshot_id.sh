#!/bin/bash 

. ~/.bash_profile

sqlplus -s / as sysdba << EOF

WHENEVER SQLERROR EXIT FAILURE
SET FEEDBACK OFF
SET HEADING OFF
SET PAGES 0

SELECT LTRIM(MAX(snap_id))
FROM dba_hist_snapshot s
JOIN v\$database d ON d.dbid = s.dbid;

EOF