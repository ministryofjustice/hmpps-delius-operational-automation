#!/bin/bash 
 
 . ~/.bash_profile

sqlplus -s / as sysdba << EOF

WHENEVER SQLERROR EXIT FAILURE
SET FEEDBACK ON
SET HEADING OFF
SET VERIFY OFF

DEFINE DATEFORMAT='DD-MON-YYYY HH24:MI:SS'

COLUMN resetlogs NEW_VALUE RESETLOGS_TIME NOPRINT

SELECT TO_CHAR(created,'&&DATEFORMAT') resetlogs FROM v\$database;

/*
   Drop and recreate the staging table in case the base tables structure has changed.
*/
BEGIN
FOR x IN (SELECT table_name
          FROM   dba_tables
          WHERE  owner = 'DELIUS_USER_SUPPORT'
          AND    table_name IN ('STAGE_PROBATION_AREA_USER','STAGE_STAFF','STAGE_STAFF_TEAM'))
LOOP
  EXECUTE IMMEDIATE 'DROP TABLE delius_user_support.'||x.table_name;
END LOOP;
END;
/

CREATE TABLE delius_user_support.stage_probation_area_user AS
SELECT  user_id,
        probation_area_id,
        created_by_user_id,
        last_updated_user_id,
        training_session_id
FROM delius_app_schema.probation_area_user
WHERE 1=2;
    
/*
   staff_id is not fixed between different databases and my have diverged between production and clones.
   However, there is a 1-to-1 relationship between user_id (which is fixed in all environments) and staff_id so this can
   be used to identify the same staff member in a cloned database.   (Note this is not enforced by a unique constraint
   on the USER_ table but the relationship is implied)
   Therefore the user_id must also be included in the staged Staff data.
*/

CREATE TABLE delius_user_support.stage_staff AS
SELECT  u.user_id,
        s.staff_id,
        s.surname,
        s.forename,
        s.forename2,
        s.staff_grade_id,
        s.title_id,
        s.officer_code,
        s.created_by_user_id,
        s.last_updated_user_id,
        s.training_session_id,
        s.private,
        s.sc_provider_id,
        s.probation_area_id
FROM       delius_app_schema.staff s
INNER JOIN delius_app_schema.user_ u
ON         s.staff_id = u.staff_id
WHERE 1=2;
    
CREATE TABLE delius_user_support.stage_staff_team AS
SELECT staff_id,
        team_id,
        created_by_user_id,
        last_updated_user_id,
        training_session_id
FROM delius_app_schema.staff_team
WHERE 1=2;

INSERT INTO delius_user_support.stage_probation_area_user
SELECT  pau.user_id,
        pau.probation_area_id,
        pau.created_by_user_id,
        pau.last_updated_user_id,
        pau.training_session_id
FROM delius_app_schema.probation_area_user pau
JOIN delius_app_schema.user_ u ON u.user_id = pau.user_id
AND pau.created_datetime >= TO_DATE('&&RESETLOGS_TIME','&&DATEFORMAT');

INSERT INTO delius_user_support.stage_staff
SELECT  u.user_id,
        s.staff_id,
        s.surname,
        s.forename,
        s.forename2,
        s.staff_grade_id,
        s.title_id,
        s.officer_code,
        s.created_by_user_id,
        s.last_updated_user_id,
        s.training_session_id,
        s.private,
        s.sc_provider_id,
        s.probation_area_id
FROM       delius_app_schema.staff s
INNER JOIN delius_app_schema.user_ u 
ON         u.staff_id = s.staff_id
AND        s.created_datetime >= TO_DATE('&&RESETLOGS_TIME','&&DATEFORMAT');

INSERT INTO delius_user_support.stage_staff_team
SELECT  st.staff_id,
        st.team_id,
        st.created_by_user_id,
        st.last_updated_user_id,
        st.training_session_id
FROM delius_app_schema.staff_team st
JOIN delius_app_schema.user_ u ON u.staff_id = st.staff_id
AND st.created_datetime >= TO_DATE('&&RESETLOGS_TIME','&&DATEFORMAT');

DECLARE

lc_count  INTEGER(1);

BEGIN

  SELECT COUNT(*)
  INTO lc_count
  FROM dba_directories
  WHERE directory_name = 'DATA_PUMP_DIR'
  AND directory_path = '/u01/app/oracle/admin/${ORACLE_SID}/dpdump/';

  IF lc_count = 0
  THEN
    EXECUTE IMMEDIATE q'[CREATE OR REPLACE DIRECTORY data_pump_dir AS '/u01/app/oracle/admin/${ORACLE_SID}/dpdump/']';
  END IF;
END;
/

EOF
RC=$?

# Fail if tables were not populated correctly
[[ $RC -gt 0 ]] && exit $RC

expdp \"/ as sysdba\" tables=delius_user_support.stage_probation_area_user,delius_user_support.stage_staff,delius_user_support.stage_staff_team directory=data_pump_dir dumpfile=datasets.dmp logfile=expdatasets.log reuse_dumpfiles=y