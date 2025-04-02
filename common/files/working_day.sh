#!/bin/bash
#
# Calculates if this is a working day for Probation.
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

SELECT
    CASE
        WHEN to_char(sysdate, 'DAY') IN ( 'SATURDAY', 'SUNDAY' ) THEN
            'NO'
        WHEN rd.standard_reference_list_id IS NOT NULL THEN
            'NO'
        ELSE
            'YES'
    END working_day
FROM
    dual d
    OUTER APPLY (
        SELECT
            *
        FROM
            delius_app_schema.r_reference_data_master   rrdm
            LEFT JOIN delius_app_schema.r_standard_reference_list rsrl ON rrdm.reference_data_master_id = rsrl.reference_data_master_id
        WHERE
                rrdm.code_set_name = 'NON WORKING DAYS'
            AND rsrl.code_value = to_char(sysdate, 'DDMMYY')
        FETCH FIRST 1 ROWS ONLY
    )    rd;

EOF