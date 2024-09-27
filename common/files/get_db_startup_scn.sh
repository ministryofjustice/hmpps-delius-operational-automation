#!/bin/bash
# If we are restarting after a refresh, flashback or restore we need to start
# replicating audit data from after the Latest RESETLOGS Change for the Database.
#
# (Previous we were using the RESETLOGS time but this appeared to not work
#  properly for reasons that were not clear - DMS would start looking for
#  redo from a long time BEFORE the time of the RESETLOGS)
#
#  NB: We need to add 1 to the Resetlogs SCN.  This is because AWS queries
#  the V$DATABASE_INCARNATION view which a strict less than predicate (RESETLOGS# < SCN)
#  so we can only find the current incarnation if the reset SCN is higher than the
#  RESETLOGS SCN by at least 1.
#
. ~/.bash_profile
sqlplus -s / as sysdba <<EOSQL
SET HEAD OFF
SET FEED OFF
SET PAGES 0
COL resetlogs_scn FORMAT 99999999999999
SELECT resetlogs_change# + 1 resetlogs_scn
FROM v\$database;
EXIT
EOSQL