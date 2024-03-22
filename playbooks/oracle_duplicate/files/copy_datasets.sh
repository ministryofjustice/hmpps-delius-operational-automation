#!/bin/bash 
 
 . ~/.bash_profile

sqlplus -s / as sysdba << EOF

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

impdp \"/ as sysdba\" directory=data_pump_dir dumpfile=datasets.dmp job_name=impdatasets table_exists_action=replace logfile=impdatasets.log

sqlplus -s / as sysdba << EOF

WHENEVER SQLERROR EXIT FAILURE
SET FEEDBACK OFF
SET HEADING OFF
SET VERIFY OFF
SET SERVEROUTPUT ON

DECLARE

l_count         NUMBER;
LC_DATE_TIME    DATE:=SYSDATE;
l_staff_count   INTEGER := 0;

-- Insertion of Staff Records will require generation of new STAFF_IDs and
-- new Officer Codes to avoid conflicting with existing data.
l_new_staff_id       delius_app_schema.staff.staff_id%TYPE;
l_new_officer_code   delius_app_schema.staff.officer_code%TYPE;

/*
   This function is used to generate the next sequential Office Code
   based on the one supplied.   This is a 7 character alphanumeric
   containing A-Z and 0-9.   We simply increment the final character
   by one and if it loops, set it to zero, and recursive back to
   the next last character in the string.
*/
FUNCTION next_sequential_string(p_input VARCHAR2) RETURN VARCHAR2 IS
  l_char CHAR(1);
  l_rest VARCHAR2(32767);
  l_result VARCHAR2(32767);
BEGIN
  IF p_input IS NULL THEN
    RETURN NULL;
  END IF;

  -- Split the string into the last character and the rest
  l_char := SUBSTR(p_input, -1);
  l_rest := SUBSTR(p_input, 1, LENGTH(p_input) - 1);

  -- Check the character type and move to the next one accordingly
  CASE 
    WHEN l_char BETWEEN '0' AND '8' THEN
      l_result := l_rest || CHR(ASCII(l_char) + 1);
    WHEN l_char = '9' THEN
      l_result := l_rest || 'A';
    WHEN l_char BETWEEN 'A' AND 'Y' THEN
      l_result := l_rest || CHR(ASCII(l_char) + 1);
    WHEN l_char = 'Z' THEN
      -- If we reached the 'Z', then reset to '0' and recurse on the rest of the string
      l_result := next_sequential_string(l_rest) || '0';
      -- Catch all for unexpected characters (in case of bad data)
    ELSE 
      l_result := next_sequential_string(l_rest) || '0';
  END CASE;

  RETURN l_result;
END next_sequential_string;

/*
   This function is used to get the new unused Officer Code by repeatedly 
   incrementing the Office Code string until we reach one that is not already
   used within the same Probation Area.
*/
FUNCTION next_free_officer_code ( p_officer_code      delius_app_schema.staff.officer_code%TYPE
                                 ,p_probation_area_id delius_app_schema.staff.probation_area_id%TYPE ) 
RETURN VARCHAR2 IS
    l_matches INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO   l_matches
    FROM   delius_app_schema.staff
    WHERE  probation_area_id = p_probation_area_id
    AND    officer_code = p_officer_code;

    -- If no existing matches then use the current officer code
    IF l_matches = 0
    THEN
       RETURN p_officer_code;
    ELSE
       -- Otherwise try using the next sequential officer code
       RETURN next_free_officer_code(next_sequential_string(p_officer_code),p_probation_area_id);
    END IF;
END next_free_officer_code;

BEGIN

    SELECT COUNT(*) 
    INTO l_count
    FROM delius_user_support.stage_probation_area_user;

    DBMS_OUTPUT.PUT_LINE('No of staged_probation_area_user rows: '||l_count);

    SELECT COUNT(*) 
    INTO l_count
    FROM delius_user_support.stage_staff;

    DBMS_OUTPUT.PUT_LINE('No of staged_staff rows: '||l_count);

    SELECT COUNT(*) 
    INTO l_count
    FROM delius_user_support.stage_staff_team;

    DBMS_OUTPUT.PUT_LINE('No of staged_staff_team rows: '||l_count);

    MERGE INTO delius_app_schema.probation_area_user p
    USING
    (
        SELECT *
        FROM delius_user_support.stage_probation_area_user
    ) s
    ON (s.user_id = p.user_id AND s.probation_area_id = p.probation_area_id)
    WHEN NOT MATCHED THEN
    INSERT
    (
        user_id,
        probation_area_id,
        row_version,
        created_datetime,
        created_by_user_id,
        last_updated_datetime,
        last_updated_user_id,
        training_session_id)
    VALUES  
    (
        s.user_id,
        s.probation_area_id,
        0,
        LC_DATE_TIME,
        s.created_by_user_id,
        LC_DATE_TIME,
        s.last_updated_user_id,
        s.training_session_id);

    DBMS_OUTPUT.PUT_LINE('No of probation_area_user rows created: '||SQL%ROWCOUNT);

    -- Loop through all Users in the Staging STAFF table who have not
    -- already been assigned a STAFF record (we dot overwrite any existing
    -- assignments even if they differ; we only create new ones)
    FOR x IN (
    SELECT  ss.user_id,
            ss.surname,
            ss.forename,
            ss.forename2,
            ss.staff_grade_id,
            ss.title_id,
            ss.officer_code,
            ss.created_by_user_id,
            ss.last_updated_user_id,
            ss.training_session_id,
            ss.private,
            ss.sc_provider_id,
            ss.probation_area_id
    FROM      delius_user_support.stage_staff ss
    LEFT JOIN delius_app_schema.user_ u
    ON        ss.user_id = u.user_id
    WHERE     u.staff_id IS NULL
    ) LOOP
       DBMS_OUTPUT.put_line('Inserting '||x.forename||' '||x.surname);
       DBMS_OUTPUT.put_line('OFFICER_CODE is '||x.officer_code);
       l_new_officer_code := next_free_officer_code(x.officer_code,x.probation_area_id);
       IF l_new_officer_code != x.officer_code THEN
          DBMS_OUTPUT.put_line('Changed OFFICER_CODE from '||x.officer_code||' to '||l_new_officer_code||' to avoid duplication.');
       END IF;

       -- Create a new STAFF_ID to avoid conflicting with existing ones
       l_new_staff_id := delius_app_schema.staff_id_seq.NEXTVAL;

       INSERT INTO delius_app_schema.staff
       (staff_id,
        start_date,
        surname,
        end_date,
        forename,
        row_version,
        forename2,
        staff_grade_id,
        title_id,
        officer_code,
        created_by_user_id,
        last_updated_user_id,
        created_datetime,
        last_updated_datetime,
        training_session_id,
        private,
        sc_provider_id,
        probation_area_id)
       VALUES  
        (l_new_staff_id,
        TRUNC(LC_DATE_TIME),
        x.surname,
        NULL,
        x.forename,
        0,
        x.forename2,
        x.staff_grade_id,
        x.title_id,
        l_new_officer_code,
        x.created_by_user_id,
        x.last_updated_user_id,
        LC_DATE_TIME,
        LC_DATE_TIME,
        x.training_session_id,
        x.private,
        x.sc_provider_id,
        x.probation_area_id);
        
       -- Update the corresponding USER_ record to point to
       -- the newly created STAFF record
       UPDATE delius_app_schema.user_
       SET    staff_id = l_new_staff_id
       WHERE  user_id = x.user_id;
       
       l_staff_count := l_staff_count + 1;
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('No of staff rows created: '||l_staff_count);

/*
  
    When merging Staff Team data, the old values of the STAFF_ID in the Staging table
    are now obsolete, but we can use the USER_ID to find the corresponding new
    STAFF_ID, so we join via the USER_ table to get this value.

    Note that we do not preserve any Teams from the database being refreshed, so
    we must exclude any Staff Team records associated with Teams that do not
    exsting in the current database.
    
*/
    MERGE INTO delius_app_schema.staff_team st
    USING (
    SELECT     sst.staff_id old_staff_id,
                sst.team_id,
                sst.created_by_user_id,
                sst.last_updated_user_id,
                sst.training_session_id,
                ss.user_id,
                u.staff_id new_staff_id
    FROM       delius_user_support.stage_staff_team sst
    INNER JOIN delius_app_schema.team t
    ON         sst.team_id = t.team_id   -- Avoid linking to non-existent teams
    INNER JOIN delius_user_support.stage_staff ss
    ON         sst.staff_id = ss.staff_id
    INNER JOIN delius_app_schema.user_ u
    ON         ss.user_id = u.user_id) m
    ON (st.staff_id = m.new_staff_id AND st.team_id = m.team_id)
    WHEN NOT MATCHED
    THEN
        INSERT
        (
            staff_id,
            team_id,
            row_version,
            created_by_user_id,
            created_datetime,
            last_updated_user_id,
            last_updated_datetime,
            training_session_id
        )
        VALUES
        (   
            m.new_staff_id,
            m.team_id,
            0,
            m.created_by_user_id,
            LC_DATE_TIME,
            m.last_updated_user_id,
            LC_DATE_TIME,
            m.training_session_id);

    DBMS_OUTPUT.PUT_LINE('No of staff_team rows created: '||SQL%ROWCOUNT);

END;
/
EOF