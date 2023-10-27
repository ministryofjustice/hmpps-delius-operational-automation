#!/bin/bash
# 
#  Some users do not have access to the production Delius application but do have access to the production data
#  through other production-like environments.   In order to support auditing of the activities of these users
#  they must be added as "stub" records into the production database to which audited interaction records may
#  be linked.   As they do not have a corresponding LDAP entry this does not provide login permissions for the
#  production application.
#
#  The location of the Audit Stub Directory and File must be provided.   A JSON file is expected of the format:
#
#  "Username": {
#      "email": "Email",
#      "forename": "Forename",
#      "forename2": "Optional Additional Forename"
#      "surname": "Surname",
#      "notes": "Notes",
#      "type": "Type"
#      "end_date": "End Date for Closed Accounts (Not Set for Open Accounts)"
#   },
#
#

. ~/.bash_profile

export AUDIT_STUB_DIRECTORY=$1
export AUDIT_STUB_FILE=$2

sqlplus -s / as sysdba <<EOF
WHENEVER SQLERROR EXIT FAILURE

-- Create Oracle Directory corresponding to the Linux directory where the JSON file is located
-- This is only used temporarily for the loading of this data and is then removed.
CREATE OR REPLACE DIRECTORY audit_stub_directory AS '${AUDIT_STUB_DIRECTORY}';

MERGE /*+ WITH_PLSQL */ INTO (SELECT * FROM delius_app_schema.user_ WHERE created_datetime IS NOT NULL OR (created_datetime IS NULL and end_date IS NULL)) u
USING
( WITH
    FUNCTION add_distinguished_name (
        p_dir      VARCHAR2,
        p_filename VARCHAR2
    ) RETURN CLOB IS
        l_users json_object_t;
        l_keys  json_key_list;
        l_bfile BFILE;
        l_blob  BLOB;
    BEGIN
        -- Stub Users are defined in an external JSON file.   Read this into a BLOB for processing.
        DBMS_LOB.createtemporary(l_blob, false);
        l_bfile := bfilename(p_dir, p_filename);
        DBMS_LOB.fileopen(l_bfile, DBMS_LOB.file_readonly);
        DBMS_LOB.loadfromfile(l_blob, l_bfile, DBMS_LOB.getlength(l_bfile));
        DBMS_LOB.fileclose(l_bfile);
        -- Define the BLOB as a JSON Object
        l_users := json_object_t.parse(l_blob);
        l_keys := l_users.GET_KEYS;
        -- Loop through all the keys in JSON Object and patch them in as an attribute.   This makes
        -- it possible to reference them from within the JSON_TABLE function.
        FOR n IN l_keys.FIRST..l_keys.LAST LOOP
            l_users.PATCH(REPLACE('[{"op": "add", "path": "/(%key%)/distinguished_name", "value": "(%key%)"}]', '(%key%)', l_keys(n)));
        END LOOP;
        RETURN l_users.TO_CLOB();
    END;
     --
    FUNCTION validate_end_date(
       p_distinguished_name VARCHAR2, 
       p_existing_end_date DATE, 
       p_new_end_date DATE)
    RETURN DATE IS
    BEGIN
       -- We should never update the end date of an existing stub user to null (if it is not already null)
       -- Instead raise an error that an unexpected manual update of the stub user has been performed through the application
       IF p_existing_end_date IS NOT NULL
       AND p_new_end_date IS NULL
       THEN
          RAISE_APPLICATION_ERROR(-20319,'User '||p_distinguished_name||' has been end-dated within the application but is still active in the Audit Stub Users data file.');
       END IF;
       RETURN p_new_end_date;
    END;   
stub_users AS
(
SELECT j.*
FROM   JSON_TABLE (
         add_distinguished_name(
           'AUDIT_STUB_DIRECTORY', '${AUDIT_STUB_FILE}'
         )
    , '\$.*'
  COLUMNS (
    user_type          VARCHAR2(300) PATH '\$.type'
 ,  distinguished_name VARCHAR2(300) PATH '\$.distinguished_name'
 ,  email              VARCHAR2(300) PATH '\$.email'
 ,  forename           VARCHAR2(300) PATH '\$.forename'
 ,  forename2          VARCHAR2(300) PATH '\$.forename2'
 ,  surname            VARCHAR2(300) PATH '\$.surname'
 ,  notes              CLOB          PATH '\$.notes'
 ,  end_date           DATE          PATH '\$.end_date'     -- Dates in JSON are expected to be in ISO 8601 format
  )
) j
),
stub_users_expanded_names AS
(
SELECT    -- Some user names are missing - derive this from the email address as Forename and Surname are mandatory fields
distinguished_name,
email,
notes,
user_type,
forename original_forename,
forename2,
surname original_surname,
CASE WHEN forename IS NOT NULL THEN forename ELSE INITCAP(REGEXP_REPLACE(email,'^(\w+?)[A-Z\.@].*\$','\1')) END forename,
CASE WHEN surname IS NOT NULL THEN surname ELSE INITCAP(TRANSLATE(REGEXP_REPLACE(email,'^[A-Z]{0,1}[a-z]*\.{0,1}([A-Z]{0,1})(\w+\-{0,1}\w*)([A-Z@]|\$).*\$','\1\2'),'~0123456789','~')) END surname,
end_date
FROM stub_users
),
stub_users_validated_end_date AS
(
SELECT s.distinguished_name
  ,VALIDATE_END_DATE(
    p_distinguished_name => s.distinguished_name
   ,p_existing_end_date  => eu.end_date
   ,p_new_end_date       => s.end_date
) validated_end_date
FROM       stub_users s
LEFT JOIN  delius_app_schema.user_ eu
ON         s.distinguished_name = eu.distinguished_name
AND        eu.notes LIKE 'This is a Stub Record%'
)
SELECT 
u1.user_id data_maintenance_id,
suen.distinguished_name,
suen.surname,
suen.forename,
suen.forename2,
suen.end_date,
ved.validated_end_date,
'This is a Stub Record used to identify non-production users for audit purposes when that user may have access to production data in another environment. ' ||
CASE WHEN suen.email             IS NOT NULL THEN CHR(10)||'User email is '||suen.email ELSE NULL END ||
CASE WHEN suen.user_type         IS NOT NULL THEN CHR(10)||'The user type is '||suen.user_type ELSE NULL END ||
CASE WHEN suen.notes             IS NOT NULL THEN CHR(10)||'Additional Notes: '||suen.notes ELSE NULL END ||
CASE WHEN suen.original_forename IS NULL OR suen.original_surname IS NULL THEN CHR(10)||'Please note that the name of the user was unavailable and has been derived from the email address.  Please confirm this information.' END notes
FROM stub_users_expanded_names suen
RIGHT JOIN stub_users_validated_end_date ved           -- Use right join to workaround JSON error (invalid index); in practice this is an inner join as all rows will match
ON    suen.distinguished_name = ved.distinguished_name
CROSS JOIN delius_app_schema.user_ u1
WHERE u1.distinguished_name IN ('Data Maintenance','[Data Maintenance]')
) r ON ( u.distinguished_name = r.distinguished_name )
WHEN MATCHED THEN UPDATE
SET u.surname = r.surname,
    u.forename = r.forename,
    u.forename2 = r.forename2,
    u.end_date = r.validated_end_date,
    u.notes = r.notes,
    u.row_version = u.row_version + 1,
    u.last_updated_user_id = r.data_maintenance_id,
    u.last_updated_datetime = sysdate
WHERE
    u.notes LIKE 'This is a Stub Record%'
    AND (    NVL(u.surname,'__NULL__') != NVL(r.surname,'__NULL__')
          OR NVL(u.forename,'__NULL__') != NVL(r.forename,'__NULL__')
          OR NVL(u.forename2,'__NULL__') != NVL(r.forename2,'__NULL__')
          OR ((u.end_date IS NULL AND r.end_date IS NOT NULL) OR (u.end_date IS NOT NULL AND r.end_date IS NULL))  -- End-dated users must be end-dated in all environments; however we can disregard differences in the dates
          OR dbms_lob.compare(u.notes, r.notes) > 0 )
WHEN NOT MATCHED THEN
INSERT (
    user_id,
    surname,
    forename,
    forename2,
    notes,
    distinguished_name,
    private,
    organisation_id,
    created_by_user_id,
    created_datetime,
    end_date,
    last_updated_user_id,
    last_updated_datetime )
VALUES
    ( delius_app_schema.user_id_seq.nextval,
    r.surname,
    r.forename,
    r.forename2,
    r.notes,
    r.distinguished_name,
    0,
    0,
    r.data_maintenance_id,
    sysdate,
    r.end_date,
    r.data_maintenance_id,
    sysdate )
/

COMMIT;

DROP DIRECTORY audit_stub_directory;

EXIT
EOF