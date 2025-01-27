#!/bin/bash
#
# Move an existing table which is in the wrong flashback archive (due to retention requirements)
#

[[ -z ${OWNER_NAME} ]] && echo "Table OWNER_NAME must be specified" && exit 1
[[ -z ${TABLE_NAME} ]] && echo "TABLE_NAME must be specified" && exit 1
[[ -z ${NUMBER_OF_YEARS} ]] && echo "NUMBER_OF_YEARS of retention must be specified" && exit 1

. ~/.bash_profile

sqlplus -s /  as sysdba <<EOF
SET LINES 1000
SET PAGES 0
SET FEEDBACK OFF
SET HEADING OFF
WHENEVER SQLERROR EXIT FAILURE

-- Create table to export existing history
-- Note: this is hardcoded to TEMP_HISTORY by Oracle
BEGIN
DBMS_FLASHBACK_ARCHIVE.create_temp_history_table(
   owner_name1=>'${OWNER_NAME}',
   table_name1=>'${TABLE_NAME}');
END;
/

-- Get name of existing flashback history table
COLUMN archive_table_name NEW_VALUE flashback_history_table

SELECT archive_table_name
FROM   dba_flashback_archive_tables
WHERE  owner_name = '${OWNER_NAME}'
AND    table_name = '${TABLE_NAME}';

-- Run export of existing history
INSERT /*+ append */ 
INTO   ${OWNER_NAME}.temp_history 
SELECT *
FROM   ${OWNER_NAME}.&&flashback_history_table;

-- Disassociate table with existing archive
ALTER TABLE ${OWNER_NAME}.${TABLE_NAME} NO FLASHBACK ARCHIVE;

-- Need to pause before adding table back into flashback archive
-- to abvoid ORA-55624 error
BEGIN
   DBMS_SESSION.sleep(2);
END;
/

-- Associate table with new archive
ALTER TABLE ${OWNER_NAME}.${TABLE_NAME} FLASHBACK ARCHIVE delius_${NUMBER_OF_YEARS}_year_fda;

-- Reimport the data history
BEGIN
  DBMS_FLASHBACK_ARCHIVE.import_history (
    owner_name1       => '${OWNER_NAME}',
    table_name1       => '${TABLE_NAME}', 
    temp_history_name => 'TEMP_HISTORY');
END;
/

EXIT
EOF