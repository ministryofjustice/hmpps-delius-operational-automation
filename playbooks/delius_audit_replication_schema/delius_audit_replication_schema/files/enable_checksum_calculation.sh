#!/bin/bash
#
#  Enable the Audited Interaction Data Checksumming Scheduler Job
#

. ~/.bash_profile

sqlplus -L -S /nolog <<EOSQL
connect / as sysdba
SET PAGES 0
SET FEEDBACK OFF
SET ECHO OFF

BEGIN
   DBMS_SCHEDULER.enable('DELIUS_AUDIT_DMS_POOL.AUDIT_CHECKSUM_CALCULATE_JOB');
END;
/

EXIT
EOSQL