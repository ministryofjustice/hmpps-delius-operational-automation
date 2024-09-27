#!/bin/bash
#
# Calculate one final audited interaction checksum prior to removing the database
#

. ~/.bash_profile

sqlplus / as sysdba <<-EOSQL

SET SERVEROUT ON

DECLARE
l_checksum_job_enabled INTEGER;
BEGIN
SELECT COUNT(*)
INTO   l_checksum_job_enabled
FROM   dba_scheduler_jobs
WHERE  owner = 'DELIUS_AUDIT_DMS_POOL'
AND    job_name = 'AUDIT_CHECKSUM_CALCULATE_JOB'
AND    enabled = 'TRUE';

IF l_checksum_job_enabled = 1
THEN
    -- The p_final flag ensures we get a checksum for all audit data
    -- right up to the current time.  Application sessions should have
    -- been blocked by this point so there is no risk of new data
    -- appearing during or after the final checksum calculation.
    DBMS_OUTPUT.put_line('Calculating final checksum before shutdown.');
    delius_audit_dms_pool.pkg_checksum.calculate_new_checksum(p_final => TRUE);
END IF;
END;
/

EXIT
EOSQL
