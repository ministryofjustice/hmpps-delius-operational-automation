#!/bin/bash
#
#  Disable or Enable Delius Scheduler Tasks (Custom Multi-Threaded Worker Processes)
# 

# Action should be block or unblock
ACTION=$1
echo "Implementing ${ACTION}"

. ~/.bash_profile

sqlplus -s / as sysdba <<EOSQL
SET SERVEROUT ON
WHENEVER SQLERROR EXIT FAILURE

BEGIN
IF '${ACTION}' = 'block'
THEN
   DBMS_OUTPUT.put_line('PRF_MT_stop_workers');
   delius_app_schema.PKG_PERF_COLLECTOR.PRF_MT_stop_workers;
ELSIF '${ACTION}' = 'unblock'
THEN
   DBMS_OUTPUT.put_line('PRF_MT_clear_stop_flags');
   delius_app_schema.PKG_PERF_COLLECTOR.PRF_MT_clear_stop_flags;
END IF;
END;
/
EOSQL