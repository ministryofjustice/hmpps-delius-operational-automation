#!/bin/bash
#
#  Merge in the Alfresco Wallet Location
#
. ~oracle/.bash_profile

sqlplus -s /  as sysdba <<EOF
SET LINES 1000
SET PAGES 0
SET FEEDBACK OFF
SET HEADING OFF
WHENEVER SQLERROR EXIT FAILURE

MERGE INTO delius_app_schema.spg_control sc
USING dual d 
ON (sc.control_code='ALFWALLET')
WHEN MATCHED
THEN UPDATE SET value_string='file:${ALFRESCO_WALLET_LOCATION}'
WHEN NOT MATCHED
THEN INSERT (spg_control_id,control_code,control_name,control_type,value_string,value_number,value_date)
     VALUES (2003,'ALFWALLET','Alfresco API URL','C','file:${ALFRESCO_WALLET_LOCATION}',NULL,SYSDATE);

COMMIT;

EXIT
EOF