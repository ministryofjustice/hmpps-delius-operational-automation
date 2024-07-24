#!/bin/bash 
 
. ~/.bash_profile

sqlplus -s / as sysdba << EOF

WHENEVER SQLERROR EXIT FAILURE
SET FEEDBACK ON
SET HEADING OFF
SET VERIFY OFF

MERGE INTO delius_app_schema.nd_parameter nd
USING  (SELECT 'ARN_LOCATION' nd_parameter,'https://preprod.hmpps-assessments.service.justice.gov.uk' nd_value_string FROM dual UNION
        SELECT 'CREATE_VARY_LICENCE_URL' nd_parameter ,'https://create-and-vary-a-licence-preprod.hmpps.service.justice.gov.uk' nd_value_string FROM dual UNION
        SELECT 'FREE_TEXT_SEARCH_FEEDBACK_LINK' nd_parameter,'https://forms.gle/vZxfVZ6vqUDofGAD8' nd_value_string FROM dual UNION
        SELECT 'WORKFORCE_MANAGEMENT' nd_parameter,'https://workload-measurement-preprod.hmpps.service.justice.gov.uk' nd_value_string FROM dual UNION
        SELECT 'HOME_PAGE_FEEDBACK_LINK' nd_parameter,'https://docs.google.com/forms/d/e/1FAIpQLSeqCGcg8l6obob1_uUb_OP6SS3Nj78Sny4V2CuBpmtp294WpA/viewform' nd_value_string FROM dual UNION
        SELECT 'CREATE_RECALL_URL' nd_parameter,'https://consider-a-recall-preprod.hmpps.service.justice.gov.uk/' nd_value_string FROM dual UNION
        SELECT 'RESETTLEMENT_PASSPORT_URL' nd_parameter,'https://resettlement-passport-ui-preprod.hmpps.service.justice.gov.uk/' nd_value_string FROM dual UNION
        SELECT 'AP_REFERRAL_URL' nd_parameter ,'https://approved-premises-preprod.hmpps.service.justice.gov.uk/' nd_value_string FROM dual) update_data
ON (update_data.nd_parameter = nd.nd_parameter)
WHEN MATCHED THEN UPDATE SET nd.nd_value_string = update_data.nd_value_string;