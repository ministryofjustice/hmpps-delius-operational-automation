#!/bin/bash
# End Database Backup

. ~/.bash_profile

# We ignore the case of some or all files already not being in backup mode
sqlplus -s / as sysdba <<EOSQL
SET HEADING OFF
SET PAGES 0
DECLARE
   e_some_files_not_in_backup   EXCEPTION;  
   e_all_files_not_in_backup    EXCEPTION;
   PRAGMA EXCEPTION_INIT (e_some_files_not_in_backup, -1260);  
   PRAGMA EXCEPTION_INIT (e_all_files_not_in_backup, -1142);
BEGIN
   EXECUTE IMMEDIATE 'ALTER DATABASE END BACKUP';
EXCEPTION
   WHEN e_some_files_not_in_backup OR e_all_files_not_in_backup
   THEN NULL;
END;
/
EXIT
EOSQL
