#!/bin/bash

. ~/.bash_profile
OBSERVER_DIR=/u01/app/oracle/dg_observer
mkdir ${OBSERVER_DIR}

# Wait until all the databases in the configuration are running before performing any action.
# This supports automatic stop/start of environments as we do not want the Observer to be
# performing a failover during the morning startup.
LOOP_COUNTER=0
SQL_TEST="whenever oserror exit failure"
TEST_CODE=1

echo "Waiting for databases to become available..."
while [[ ${LOOP_COUNTER} -le 600 && ${TEST_CODE} -gt 0 ]];
do
   echo "Sleeping 1 minute..."
   sleep 60
   echo ${SQL_TEST} | sqlplus -S -L /@${DATABASE_NAME} as sysdba
   TEST_PRIMARY=$?
   [[ $TEST_PRIMARY -eq 0 ]] && echo "Primary is available" || echo "Primary is unavailable"
   if [ "$STANDBYDB1_HOSTNAME" != "none" ]; then
      echo ${SQL_TEST} | sqlplus -S -L /@${DATABASE_NAME}S1 as sysdba
      TEST_STANDBYDB1=$?
      [[ $TEST_STANDBYDB1 -eq 0 ]] && echo "1st Standby is available" || echo "1st Standby is unavailable"
   else
      TEST_STANDBYDB1=0
   fi
   if [ "$STANDBYDB2_HOSTNAME" != "none" ]; then
      echo ${SQL_TEST} | sqlplus -S -L /@${DATABASE_NAME}S2 as sysdba
      TEST_STANDBYDB2=$?
      [[ $TEST_STANDBYDB1 -eq 0 ]] && echo "2nd Standby is available" || echo "2nd Standby is unavailable"
   else
      TEST_STANDBYDB2=0
   fi
   TEST_CODE=$((TEST_PRIMARY+TEST_STANDBYDB1+TEST_STANDBYDB2))
   LOOP_COUNTER=$((LOOP_COUNTER+60))
done

if [[ $TEST_CODE -gt 0 ]];
then
   echo "One or more databases in the configuration is unavailable.  Aborting..."
   exit 1
fi

echo "Starting observer..."
# We first stop any previous observers in the configuration which may have been left
# inactive from a previous task run.
# We start the observer in foreground mode; this keeps the docker container active
dgmgrl /@${DATABASE_NAME} <<EOL
stop observer all;
start observer file is '${OBSERVER_DIR}/dg_broker.ora' logfile is '${OBSERVER_DIR}/dg_broker.log';
EOL