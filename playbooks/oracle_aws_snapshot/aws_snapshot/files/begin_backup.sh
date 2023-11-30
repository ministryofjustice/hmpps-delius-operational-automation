#!/bin/bash
# Begin Database Backup

. ~/.bash_profile

sqlplus -s / as sysdba <<EOSQL
SET HEADING OFF
SET PAGES 0
ALTER DATABASE BEGIN BACKUP;
EXIT
EOSQL
