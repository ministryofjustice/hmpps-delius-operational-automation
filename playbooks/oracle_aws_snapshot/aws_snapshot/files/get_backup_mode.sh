#!/bin/bash
# Get Database Backup Mode

. ~/.bash_profile

sqlplus -s / as sysdba <<EOSQL
SET HEADING OFF
SET PAGES 0
SELECT CASE
WHEN datafiles = active_backups
THEN 'ACTIVE'
WHEN active_backups > 0
THEN 'PARTIAL'
ELSE 'NOT ACTIVE'
END database_backup_status
FROM
(SELECT count(*) datafiles
 FROM   v\$datafile)
CROSS JOIN
(SELECT count(*) active_backups
 FROM   v\$backup
 WHERE  status = 'ACTIVE');
EXIT
EOSQL
