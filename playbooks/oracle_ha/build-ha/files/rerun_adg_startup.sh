#!/bin/bash
#
# When an Active Data Guard Standby Database is open Read Only and it starts up before
# its associated primary there is a chance that it may encounter errors related to
# making the data files consistent to allow Read Only access.   This is because the
# required redo has not yet arrived from the primary database, and the primary database
# has not yet started.
#
# This situation is most likely to occur when an ADG database is involved in an
# automated overnight restart initiated by modernisation platform by default.  This
# process simply aborts all the hosts and then starts them up concurrently.  It is then
# a matter of chance which - primary or standby - opens first.   If it is the standby
# any data files are not in a consistent state, it will attempt to fetch the redo from
# the primary and then terminate if the primary still isn't up yet.
# The purpose of this script it to be run a short time after startup to detect this
# condition.  By now the primary should have been started, so if we attempt to start
# the standby again it should be successful as it can now fetch the required redo.
#
# This script is not required in the legacy AWS environments as startup is phased,
# and primary database hosts are always started before standby database hosts.

. ~/.bash_profile

# No action required if this is not an ADG database
START_OPTIONS=$(srvctl config database -d ${ORACLE_SID} | grep "Start options:")
[[ "${START_OPTIONS}" != "Start options: read only" ]] && echo ${START_OPTIONS} && exit 0

# No action required if database is in Read Only (or Read Only with Apply) mode
OPEN_MODE=$(echo -ne "SET HEAD OFF;\nSET PAGES 0;\n SELECT open_mode FROM v\$database;" | sqlplus -S / as sysdba | head -1)
[[ "${OPEN_MODE}" =~ "READ ONLY" ]] && echo ${OPEN_MODE} && exit 0

# If the database is already in MOUNT state then it just needs to be opened
if [[ "${OPEN_MODE}" == "MOUNTED" ]];
then
   echo "Opening database read only."
   echo "ALTER DATABASE OPEN;" | sqlplus -S / as sysdba
else
   # Otherwise we need to start it up
   echo "Attempting database start."
   srvctl start database -d ${ORACLE_SID}
fi

exit