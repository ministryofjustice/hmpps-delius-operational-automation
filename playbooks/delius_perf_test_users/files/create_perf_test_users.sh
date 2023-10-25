#!/bin/bash
# 
# Create Performance Test Users
#
# Supply:
# 1. the ORACLE_SID
# 2. ID of the User to use as a template
# 3. ID of the User to define as creator of test users
#

export PATH=$PATH:/usr/local/bin; 
export ORACLE_SID=$1; 
export TEMPLATE_USER_ID=$2
export CREATOR_USER_ID=$3
export ORAENV_ASK=NO ; 
. oraenv >/dev/null; 

sqlplus -s / as sysdba <<EOF
WHENEVER SQLERROR EXIT FAILURE

-- Create 10000 User Records
MERGE INTO delius_app_schema.user_ u
USING (SELECT 'nd.perf'||lpad(ROWNUM,5,'0') delius_username
       FROM   dual
       CONNECT BY level<=10000) n
ON ( u.distinguished_name = n.delius_username )
WHEN NOT MATCHED
THEN INSERT  (  user_id
               ,surname
               ,forename
               ,row_version
               ,distinguished_name
               ,private
               ,organisation_id
               ,created_datetime )
     VALUES  (  delius_app_schema.user_id_seq.nextval
               ,n.delius_username
               ,n.delius_username
               ,0
               ,n.delius_username
               ,0
               ,0
               ,SYSDATE );

-- Attach all these User Records to the Probation Area IDs Associated with the Template User
MERGE INTO delius_app_schema.probation_area_user a
USING (SELECT      u.user_id
                  ,pau.probation_area_id
       FROM       delius_app_schema.user_ u
       JOIN       delius_app_schema.probation_area_user pau
       ON         pau.user_id = ${TEMPLATE_USER_ID}
       WHERE      u.distinguished_name LIKE 'nd.perf%') i
ON ( a.user_id = i.user_id 
     AND a.probation_area_id = i.probation_area_id)
WHEN NOT MATCHED
THEN INSERT   (  user_id
                ,probation_area_id
                ,row_version
                ,created_datetime
                ,created_by_user_id
                ,last_updated_datetime
                ,last_updated_user_id )
     VALUES   (  i.user_id
                ,i.probation_area_id
                ,0
                ,SYSDATE
                ,${CREATOR_USER_ID}
                ,SYSDATE
                ,${CREATOR_USER_ID} );

EXIT
EOF