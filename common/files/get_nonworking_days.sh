#!/bin/bash
#
# Get Non-Working Days for Probation in JSON Format.
#
# Non-working days are Saturday and Sunday plus any holiday
# which is defined in the R_STANDARD_REFERENCE_LIST table.
#

. ~/.bash_profile

sqlplus -s /  as sysdba <<EOF
WHENEVER SQLERROR EXIT FAILURE;
SET FEEDBACK OFF
SET HEADING OFF
SET PAGES 0

SELECT JSON_MERGEPATCH(
           JSON_MERGEPATCH(
            JSON_OBJECT('code_value' VALUE JSON_OBJECT('S' VALUE rsrl.code_value)), JSON_OBJECT('code_description' VALUE JSON_OBJECT('S' VALUE rsrl.code_description))
           ), JSON_OBJECT('last_updated_datetime' VALUE JSON_OBJECT('S' VALUE TO_CHAR(rsrl.last_updated_datetime,'YYYYMMDD')))
        ) non_working_days
        FROM
            delius_app_schema.r_reference_data_master   rrdm
            LEFT JOIN delius_app_schema.r_standard_reference_list rsrl ON rrdm.reference_data_master_id = rsrl.reference_data_master_id
        WHERE
                rrdm.code_set_name = 'NON WORKING DAYS'
        AND     rsrl.last_updated_datetime > TO_DATE('${PREVIOUS_MOST_RECENT_DATA}','YYYYMMDD');
EXIT
EOF