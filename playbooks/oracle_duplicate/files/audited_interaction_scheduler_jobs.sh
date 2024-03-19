#!/bin/bash 
#
#  Where we have duplicated a database, the Audited Interaction Checksum calculation job
#  should be running (as this is potentially a client database) and the Validation job
#  should not be running (as this will not be a repository database).  These jobs may
#  not exist in all databases, so no action is taken if they do not exist.
 
 . ~/.bash_profile

sqlplus -s / as sysdba << EOF

WHENEVER SQLERROR EXIT FAILURE
SET FEEDBACK ON
SET HEADING OFF
SET VERIFY OFF
SET SERVEROUT ON

DECLARE
   l_job_status dba_scheduler_jobs.state%TYPE;
BEGIN

  SELECT COALESCE(state,'ABSENT') checksum_calculate_job
  INTO   l_job_status
  FROM   dual d
  OUTER APPLY (SELECT state 
               FROM   dba_scheduler_jobs j
               WHERE  j.owner = 'DELIUS_AUDIT_DMS_POOL'
               AND    j.job_name = 'AUDIT_CHECKSUM_CALCULATE_JOB');

  IF l_job_status = 'DISABLED'
  THEN
     DBMS_SCHEDULER.enable('DELIUS_AUDIT_DMS_POOL.AUDIT_CHECKSUM_CALCULATE_JOB');
     DBMS_OUTPUT.put_line('Enabled AUDIT_CHECKSUM_CALCULATE_JOB.');
  END IF;

  SELECT COALESCE(state,'ABSENT') checksum_validate_job
  INTO   l_job_status
  FROM   dual d
  OUTER APPLY (SELECT state 
               FROM   dba_scheduler_jobs j
               WHERE  j.owner = 'DELIUS_AUDIT_DMS_POOL'
               AND    j.job_name = 'AUDIT_CHECKSUM_VALIDATE_JOB');

  IF l_job_status = 'SCHEDULED'
  THEN
     DBMS_SCHEDULER.disable('DELIUS_AUDIT_DMS_POOL.AUDIT_CHECKSUM_VALIDATE_JOB');
     DBMS_OUTPUT.put_line('Disabled AUDIT_CHECKSUM_CALCULATE_JOB.');
  END IF;

END;
/
EXIT
EOF
