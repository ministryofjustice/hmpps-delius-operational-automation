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

# No action required if database is running
DATABASE_RUNNING=$(srvctl status database -d ${ORACLE_SID})
[[ "${DATABASE_RUNNING}" == "Database is running." ]] && echo ${DATABASE_RUNNING} && exit 0

# No action required if this is not an ADG database
START_OPTIONS=$(srvctl config database -d ${ORACLE_SID} | grep "Start options:")
[[ "${START_OPTIONS}" != "Start options: read only" ]] && echo ${START_OPTIONS} && exit 0

# Now we run through the alert log to find out if the database did not open due to an archivelog fetch failure
# Not every line of the alert log contains a timestamp, so we filter out those that match ISO 8601 timestamp format
TIMESTAMP_REGEX='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{6}\+[0-9]{2}:[0-9]{2}$'

# Get Location of Alert Log
ALERT_DIRECTORY=$(echo "show homes; exit" | adrci | grep -Ei "/$ORACLE_SID/$ORACLE_SID" | head -1)
ALERT_LOG_FILE="${ORACLE_BASE}/${ALERT_DIRECTORY}/trace/alert_${ORACLE_SID}.log"

# Get Alert Log Entries Since Latest Server Start
EPOCH_STARTUP_TIME=$(date -d "$(uptime --since)" +%s)
ISO_8601_STARTUP_TIME=$(date -d "$(uptime --since)" --iso-8601)

LOG_AFTER_STARTUP=false
# Check for an ORA-16016 in the portion of the alert log after the most recent server start
# ORA-16016 indicates that an archive log is unavailable on the standby
ORA_16016_FOUND=false
ORA_16016_FOUND_REGEX='^ORA-16016: archived log for .* unavailable$'

# Check for a completed ALTER DATABASE READ ONLY after any ORA-16016
OPEN_READ_ONLY_FOUND=false
OPEN_READ_ONLY_FOUND_REGEX='Completed: ALTER DATABASE READ ONLY'

# We scan through the alert log to find any ORA-16016 error messages which have occurred since
# the host start up time.   These indicate that it is was not possible to obtain a required
# redo log from the primary database which may be because it had not been started by the time
# that the redo was required.
#
# If the alert log is large it may take a long time to reach the portion containing entries
# since the host startup checking the timestamps line-by-line.   Therefore we shortcut this
# process by grepping for the date of the startup in the logfile and tailing only the lines
# from after this point to process.
NUMBER_OF_ALERT_LOG_LINES=$(wc -l ${ALERT_LOG_FILE} | cut -d' ' -f1)
FIRST_LINE_WITH_STARTUP_DATE=$(grep -n ${ISO_8601_STARTUP_TIME} ${ALERT_LOG_FILE} | head -1 | cut -d: -f1)
START_READING_FROM_LINE=$((NUMBER_OF_ALERT_LOG_LINES-FIRST_LINE_WITH_STARTUP_DATE))

while IFS= read -r line; do
   if [[ "${LOG_AFTER_STARTUP}" == "false" ]]; then
      TIMESTAMP=$(echo "$line" | awk '{print $1}')
      if [[ ${TIMESTAMP} =~ ${TIMESTAMP_REGEX} ]]; then
         LINE_EPOCH=$(date -d "${TIMESTAMP}" +%s)
         [[ ${LINE_EPOCH} -gt ${EPOCH_STARTUP_TIME} ]] && echo "Found alert log start for most recent boot." && LOG_AFTER_STARTUP=true
      fi
   else
      [[ $line =~ ${ORA_16016_FOUND_REGEX} ]] && ORA_16016_FOUND=true
      if [[ $line =~ ${OPEN_READ_ONLY_FOUND_REGEX} ]] && [[ "${ORA_16016_FOUND}" == "true" ]]; then
         OPEN_READ_ONLY_FOUND=true
         # Reset the ORA-16016 found flag since the database has been opened Read Only since then
         ORA_16016_FOUND=false
         # However, we continue looping in case any further ORA-16016s are found
     fi
   fi
done < <(tail --lines ${START_READING_FROM_LINE} ${ALERT_LOG_FILE})

# If an ORA-16016 was found without a subsequent OPEN READ ONLY then make attempt to start this database
if [[ "${ORA_16016_FOUND}" == "true" ]]; then
   echo "Attempting database start."
   srvctl start database -d ${ORACLE_SID}
fi

exit