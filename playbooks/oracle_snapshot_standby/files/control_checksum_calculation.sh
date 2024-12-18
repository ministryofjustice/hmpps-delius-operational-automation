#!/bin/bash
#
#  Enable or Disable the Audited Interaction Data Checksumming Scheduler Job
#  Pass in the Target State

. ~/.bash_profile

TARGET_STATE=$1

if [[ "${TARGET_STATE}" != "ENABLED" && "${TARGET_STATE}" != "DISABLED" ]];
then
   echo "Valid target states are ENABLED or DISABLED."
   exit 1
fi

sqlplus -L -S /nolog <<EOSQL
connect / as sysdba
SET PAGES 0
SET FEEDBACK OFF
SET ECHO OFF
SET SERVEROUT ON

DECLARE
   l_state                 dba_scheduler_jobs.state%TYPE;
   l_target_state CONSTANT dba_scheduler_jobs.state%TYPE := '${TARGET_STATE}';
BEGIN
   SELECT state
   INTO   l_state
   FROM   dba_scheduler_jobs
   WHERE  owner    = 'DELIUS_AUDIT_DMS_POOL'
   AND    job_name = 'AUDIT_CHECKSUM_CALCULATE_JOB';

   IF l_state = 'SCHEDULED' AND l_target_state = 'DISABLED'
   THEN
      -- Take one final audit checksum before going into snapshot standby state
      DBMS_SCHEDULER.run_job('DELIUS_AUDIT_DMS_POOL.AUDIT_CHECKSUM_CALCULATE_JOB'); 
      -- Take no further checksums until we come back out of snapshot standby state
      DBMS_SCHEDULER.disable('DELIUS_AUDIT_DMS_POOL.AUDIT_CHECKSUM_CALCULATE_JOB');
      DBMS_OUTPUT.put_line('Audit checksumming disabled.');
   END IF;

   IF l_state = 'DISABLED' AND l_target_state = 'ENABLED'
   THEN
      -- Take a new audit checksum after coming out of snapshot standby state
      DBMS_SCHEDULER.run_job('DELIUS_AUDIT_DMS_POOL.AUDIT_CHECKSUM_CALCULATE_JOB'); 
      -- Re-enable regular scheduled audit checksumming
      DBMS_SCHEDULER.enable('DELIUS_AUDIT_DMS_POOL.AUDIT_CHECKSUM_CALCULATE_JOB');
      DBMS_OUTPUT.put_line('Audit checksumming enabled.');
   END IF;
END;
/

EXIT
EOSQL