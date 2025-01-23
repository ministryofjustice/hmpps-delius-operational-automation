#!/bin/bash

# Source oracle bash profile
. ~/.bash_profile
                   
# Shutdown the database
srvctl stop database -d $ORACLE_SID

# Start the database in upgrade mode
srvctl start database -d $ORACLE_SID -o upgrade

# Wait for 60 seconds
sleep 60

# Modify the table and indexes
sqlplus -s / as sysdba <<EOF
SET LINESIZE 1000
SET PAGESIZE 0
SET FEEDBACK OFF            
SET HEADING OFF
WHENEVER SQLERROR EXIT FAILURE          

rename smon_scn_time to smon_scn_time_org;

create table smon_scn_time tablespace sysaux as select * from smon_scn_time_org;

drop index smon_scn_time_tim_idx;

create unique index smon_scn_time_tim_idx on smon_scn_time(time_mp) tablespace SYSAUX;

drop index smon_scn_time_scn_idx;

create unique index smon_scn_time_scn_idx on smon_scn_time(scn) tablespace SYSAUX;

exit
EOF

# Shutdown the database 
srvctl stop database -d $ORACLE_SID

# Start the database 
srvctl start database -d $ORACLE_SID