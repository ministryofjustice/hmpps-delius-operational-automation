#!/bin/bash
# 
# Create Hourly Snapshots and Weekly Purges
#

. ~/.bash_profile

sqlplus -s / as sysdba <<EOF
WHENEVER SQLERROR EXIT FAILURE

-- Allow PERFSTAT User Create Scheduler Jobs
GRANT CREATE JOB TO perfstat;
EXIT
EOF

sqlplus -s /nolog <<EOF
CONNECT perfstat/$1
SET LINES 1000
SET PAGES 0
SET FEEDBACK OFF
SET HEADING OFF
WHENEVER SQLERROR EXIT FAILURE

BEGIN

    DBMS_SCHEDULER.create_job (
    job_name => 'STATSPACK_SNAPSHOT',
    job_type => 'PLSQL_BLOCK',
    job_action => 'statspack.snap(i_snap_level => 6, i_modify_parameter=>''true'');',
    start_date => systimestamp,
    repeat_interval => 'FREQ=HOURLY;BYTIME=0000;BYDAY=MON,TUE,WED,THU,FRI,SAT,SUN',
    enabled => TRUE,
    comments => 'Hourly Statspack snapshot');

    DBMS_SCHEDULER.create_job (
    job_name => 'STATSPACK_PURGE',
    job_type => 'PLSQL_BLOCK',
    job_action => 'statspack.purge(i_num_days=>31,i_extended_purge=>true);',
    start_date => systimestamp,
    repeat_interval => 'FREQ=WEEKLY;BYHOUR=0;BYMINUTE=30;BYDAY=SUN',
    enabled => TRUE,
    comments => 'Weekly purge Statspack snapshot');

END;
/
EXIT
EOF