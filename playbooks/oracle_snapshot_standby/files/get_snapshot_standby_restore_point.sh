#!/bin/bash
#
# This runs on the Snapshot Standby
#  Get the Date of the Restore Point which Oracle creates when a Physical
#  Standby database has been converted to a Snapshot Standby database.
#  This is used to identify which audit data has been generated on the
#  Snapshot Standby.

. ~/.bash_profile

sqlplus -s /nolog <<EOF
SET LINES 1000
SET PAGES 0
SET FEEDBACK OFF
SET HEADING OFF
SET SERVEROUT ON
WHENEVER SQLERROR EXIT FAILURE

connect / as sysdba

SELECT TO_CHAR(MAX(time),'YYYY-MM-DD-HH24-MI-SS') max_snapshot_time
FROM   v\$restore_point 
WHERE  name LIKE 'SNAPSHOT_STANDBY%';

EXIT
EOF