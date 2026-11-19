#!/bin/bash 
 
. ~/.bash_profile

sqlplus -s / as sysdba << EOF

WHENEVER SQLERROR EXIT FAILURE
SET FEEDBACK ON
SET HEADING OFF
SET VERIFY OFF
-- Handle Ampersands in URLs
SET DEFINE OFF

/*
   This script updates production URLs in ND_PARAMETER to pre-production ones.

   It is assumed that this script will ONLY be run in Stage and Pre-Prod environments.
   Note that the Stage environment is expected to connect to Pre-Prod services (there are no separate Stage ones)
   so the mappings are the same for both Stage & Pre-Prod refreshes.

   These mappings are defined by Unilink and documented here:
   https://justiceuk-my.sharepoint.com/:x:/r/personal/nicola_hodgkinson_justice_gov_uk/_layouts/15/Doc.aspx?sourcedoc=%7B8B12EFF4-0615-4F44-AFDE-02DEF126AB09%7D&file=Delius%20Releases.xlsx&action=default&mobileredirect=true&DefaultItemOpen=1&ct=1795084961176&wdOrigin=OFFICECOM-WEB.MAIN.REC&cid=57c7bede-b50e-4060-a3ea-e756273fcebc&wdPreviousSessionSrc=unknown&wdPreviousSession=4b770e1b-fc5e-4e45-9f0a-6abbb108f225

   This script must be updated manually if contents of the spreadsheet are changed.

   Additionally there are a few URLs which map to external guidance documents or feedback forms which
   are the same for any environment.  These are included to prevent them being overwritten.

   Any URLs (identified by http or https prefixes) which do not have a defined mapping are defaulted to
   "UNKNOWN URL" to prevent any inadvertant connection into Production.

*/

MERGE INTO delius_app_schema.nd_parameter nd
USING (
    WITH mappings AS (
        SELECT 'ARN_LOCATION' nd_parameter,'https://preprod.hmpps-assessments.service.justice.gov.uk' nd_value_string FROM dual UNION
        SELECT 'CREATE_VARY_LICENCE_URL' nd_parameter ,'https://create-and-vary-a-licence-preprod.hmpps.service.justice.gov.uk' nd_value_string FROM dual UNION
        SELECT 'FREE_TEXT_SEARCH_FEEDBACK_LINK' nd_parameter,'https://forms.gle/vZxfVZ6vqUDofGAD8' nd_value_string FROM dual UNION
        SELECT 'WORKFORCE_MANAGEMENT' nd_parameter,'https://workload-measurement-preprod.hmpps.service.justice.gov.uk' nd_value_string FROM dual UNION
        SELECT 'HOME_PAGE_FEEDBACK_LINK' nd_parameter,'https://docs.google.com/forms/d/e/1FAIpQLSeqCGcg8l6obob1_uUb_OP6SS3Nj78Sny4V2CuBpmtp294WpA/viewform' nd_value_string FROM dual UNION
        SELECT 'CREATE_RECALL_URL' nd_parameter,'https://consider-a-recall-preprod.hmpps.service.justice.gov.uk/' nd_value_string FROM dual UNION
        SELECT 'RESETTLEMENT_PASSPORT_URL' nd_parameter,'https://resettlement-passport-ui-preprod.hmpps.service.justice.gov.uk/' nd_value_string FROM dual UNION
        SELECT 'AP_REFERRAL_URL' nd_parameter ,'https://approved-premises-preprod.hmpps.service.justice.gov.uk/' nd_value_string FROM dual UNION
        SELECT 'REFER_AND_MONITOR_URL' nd_parameter, 'https://find-and-refer-intervention-preprod.hmpps.service.justice.gov.uk/interventions-homepage' nd_value_string FROM DUAL UNION
        SELECT 'TRANSITIONAL_ACCOMODATION_URL' nd_parameter, 'https://transitional-accommodation-preprod.hmpps.service.justice.gov.uk' nd_value_string FROM DUAL UNION
        SELECT 'BAIL_ACCOMMODATION_URL' nd_parameter, 'https://community-accommodation-tier-2-bail-preprod.hmpps.service.justice.gov.uk/' nd_value_string FROM DUAL UNION
        SELECT 'TIER_SERVICE_URL' nd_parameter, 'https://tier-preprod.hmpps.service.justice.gov.uk/case/' nd_value_string FROM DUAL UNION
        SELECT 'CREATE_AN_EM_ORDER_URL' nd_parameter, 'https://hmpps-electronic-monitoring-create-an-order-preprod.hmpps.service.justice.gov.uk/' nd_value_string FROM DUAL UNION
        SELECT 'ACCREDITED_PROGRAMMES_URL' nd_parameter, 'https://accredited-programmes-manage-and-deliver-preprod.hmpps.service.justice.gov.uk' nd_value_string FROM DUAL UNION
        SELECT 'MANAGE_PEOPLE_ON_PROBATION_URL' nd_parameter, 'https://manage-people-on-probation-preprod.hmpps.service.justice.gov.uk' nd_value_string FROM DUAL UNION
        SELECT 'ARNS_API' nd_parameter, 'https://arns-assessment-view-api-preprod.hmpps.service.justice.gov.uk' nd_value_string FROM DUAL UNION
        SELECT 'DOMAIN_EVENTS_URL' nd_parameter, 'https://example.com' nd_value_string FROM DUAL UNION
        SELECT 'TRANSGENDER_POLICY_LINK' nd_parameter, 'https://assets.publishing.service.gov.uk/media/67360999f6920bfb5abc7b80/2024_11_14_The_Care_and_Management_of_Individuals_who_are_Transgender_PF.pdf' nd_value_string FROM DUAL UNION
        SELECT 'TRANSGENDER_GUIDANCE_LINK' nd_parameter, 'https://view.officeapps.live.com/op/view.aspx?src=https%3A%2F%2Fassets.publishing.service.gov.uk%2Fmedia%2F6736089f37aabe56c416118e%2F2024_11_14__Transgender-offender-pf-operational-guidance.docx&wdOrigin=BROWSELINK' nd_value_string FROM DUAL
    )
    SELECT nd_parameter, nd_value_string
    FROM mappings
    UNION ALL
    SELECT existing_nd.nd_parameter, 'UNKNOWN URL' nd_value_string
    FROM delius_app_schema.nd_parameter existing_nd
    WHERE (existing_nd.nd_value_string LIKE 'http://%'
        OR existing_nd.nd_value_string LIKE 'https://%')
      AND NOT EXISTS (
          SELECT 1
          FROM mappings
          WHERE mappings.nd_parameter = existing_nd.nd_parameter
      )
) update_data
ON (update_data.nd_parameter = nd.nd_parameter)
WHEN MATCHED THEN UPDATE SET nd.nd_value_string = update_data.nd_value_string;

exit
EOF