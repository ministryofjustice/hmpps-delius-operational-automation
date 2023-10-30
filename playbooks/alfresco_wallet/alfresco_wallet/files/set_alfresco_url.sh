#!/bin/bash
#
#  Merge in the Alfresco URL
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
ON (sc.control_code='ALFURL')
WHEN MATCHED
THEN UPDATE SET value_string='${ALFRESCO_URL}'
WHEN NOT MATCHED
THEN INSERT (spg_control_id,control_code,control_name,control_type,value_string,value_number,value_date)
     VALUES (2002,'ALFURL','Alfresco API URL','C','${ALFRESCO_URL}',NULL,SYSDATE);

COMMIT;

EXIT
EOF