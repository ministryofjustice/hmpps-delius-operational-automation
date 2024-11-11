#  After a database has been duplicated, the Users table should no longer be updateable by the Delius Application
#  Any required changes must be made in production and allowed to be migrated using DMS
. ~/.bash_profile

sqlplus /nolog <<EOSQL
connect / as sysdba

WHENEVER SQLERROR EXIT FAILURE;

SET SERVEROUT ON

-- Revoke any privileges will allow any user to INSERT or DELETE from the USERS_ table
-- (This is an additional precaution; trigger should be sufficient)
-- DELIUS_AUDIT_DMS_POOL is still allowed to add new Users.
-- We allow UPDATEs since UMT may update some attributes of existing users
-- (such as LAST_UPDATE_DATETIME) without it impacting audit traceability.
BEGIN
FOR x IN (SELECT grantee,privilege
          FROM   dba_tab_privs
          WHERE  owner = 'DELIUS_APP_SCHEMA'
          AND    table_name = 'USER_'
          AND    grantee != 'DELIUS_AUDIT_DMS_POOL'
          AND    privilege IN ('DELETE','INSERT'))
LOOP
  EXECUTE IMMEDIATE 'REVOKE '||x.privilege||' ON DELIUS_APP_SCHEMA.USER_ FROM '||x.grantee;
  DBMS_OUTPUT.put_line('Revoked '||x.privilege||' on USER_ from '||x.grantee);
END LOOP;
END;
/

-- Additionally we add a trigger to enforce the same restrictions for the Application Schema itself.
-- This trigger is also used to workaround a difference between NLS Date formats used in DMS
-- and those used by the Delius application.
CREATE OR REPLACE TRIGGER delius_user_support.audit_control_on_user_
FOR delete OR update OR insert ON delius_app_schema.user_
COMPOUND TRIGGER

  BEFORE STATEMENT IS
  BEGIN
      -- New Users may be added but only by the DELIUS_AUDIT_DMS_POOL User
      IF INSERTING AND USER != 'DELIUS_AUDIT_DMS_POOL'
      THEN
          RAISE_APPLICATION_ERROR(-20923,'To allow for audit trail consistency no new users may be directly added in this environment.  Instead add these to the production environment.');
      END IF;
      -- No Deletions are allowed by any user as this may remove linkage to any audit records
      IF DELETING AND USER != 'DELIUS_AUDIT_DMS_POOL'
      THEN
          RAISE_APPLICATION_ERROR(-20924,'To allow for audit trail consistency no users may be deleted in this environment.');
      END IF;

  END BEFORE STATEMENT;

  BEFORE EACH ROW IS
  BEGIN
        IF USER = 'DELIUS_AUDIT_DMS_POOL'
        THEN
            /*
            AWS DMS uses a hard-coded date and timestamp format which differs from the
            one used by Delius itself.  Whenever the USER_ table is updated, a trigger
            fires for MIS CDC capture which sets the session date format to the
            Delius one (YYYYMMDD HH24:MI:SS).   This will cause DMS to fail, so for
            the DELIUS_AUDIT_DMS_POOL session *only* which is used by DMS, we must reset
            to the expected DMS format (YYYY-MM-DD HH24:MI:SS) both before and after
            any DML on this table.

            Note that we cannot use DBMS_SESSION.SET_NLS inside of a trigger as it
            contains an implicit commit; we must therefore use ALTER SESSION.

            */
            EXECUTE IMMEDIATE 'ALTER SESSION SET nls_date_format = ''YYYY-MM-DD HH24:MI:SS''';
            EXECUTE IMMEDIATE 'ALTER SESSION SET nls_timestamp_format = ''YYYY-MM-DD HH24:MI:SS.FF9''';
            
                        
            /*
            There are multiple reasons why the Delius application may update the 
            LAST_UPDATED_USER_ID and LAST_UPDATED_DATETIME columns, but not all of these involve
            attributes which are replicated to the client database.   This can cause confusion
            if these attributes are updated but nothing appears to have changed.
            To avoid this issue, we only update LAST_UPDATED_USER_ID and LAST_UPDATED_DATETIME
            if changes have been made to the User's name, the Notes or the End Date.
            */
            IF UPDATING THEN
                IF (COALESCE(:new.end_date,SYSDATE-1000) != COALESCE(:old.end_date,SYSDATE-1000)
                  OR COALESCE(:new.notes,'NULL') != COALESCE(:old.notes,'NULL')
                  OR COALESCE(:new.distinguished_name,'NULL') != COALESCE(:old.distinguished_name,'NULL')
                  OR COALESCE(:new.surname,'NULL') != COALESCE(:old.surname,'NULL')
                  OR COALESCE(:new.forename,'NULL') != COALESCE(:old.forename,'NULL')
                  OR COALESCE(:new.forename2,'NULL') != COALESCE(:old.forename2,'NULL')) THEN
                    -- If any of the above columns have changed then we allow update of the
                    -- LAST_UPDATED_* fields
                    NULL;
                ELSE
                    -- Otherwise, prevent changes to the LAST_UPDATED_* fields as the updates
                    -- did not impact data that was replicated.
                    :new.last_updated_user_id  := :old.last_updated_user_id;
                    :new.last_updated_datetime := :old.last_updated_datetime;
                END IF;
                -- Staff IDs in stage and pre-prod are independent of those in production
                -- since these are not relevant to audit, and it may be necessary for
                -- some users to have staff records in stage and pre-prod without having
                -- corresponding records in production.  Therefore we prevent any overwriting
                -- of the staff ID                
                :new.staff_id := :old.staff_id;
            END IF;
        END IF;

      IF (UPDATING('USER_ID') OR UPDATING('DISTINGUISHED_NAME') OR UPDATING('SURNAME')
      OR UPDATING('FORENAME') OR UPDATING('FORENAME2')) AND USER != 'DELIUS_AUDIT_DMS_POOL'
      THEN
          -- A MERGE will fire both UPDATING and INSERTING actions of a trigger, so
          -- we need to detect if it is really an update, by checking the old value
          -- of the mandatory user_id is not null
          IF :old.user_id IS NOT NULL
          AND (COALESCE(:new.user_id,0) != COALESCE(:old.user_id,0)
          OR COALESCE(:new.distinguished_name,'NULL') != COALESCE(:old.distinguished_name,'NULL')
          OR COALESCE(:new.surname,'NULL') != COALESCE(:old.surname,'NULL')
          OR COALESCE(:new.forename,'NULL') != COALESCE(:old.forename,'NULL')
          OR COALESCE(:new.forename2,'NULL') != COALESCE(:old.forename2,'NULL'))
          THEN
              RAISE_APPLICATION_ERROR(-20922,'To allow for audit trail consistency no editing of personal attributes of users is permitted.');
          END IF;
      END IF;

  END BEFORE EACH ROW;

  AFTER EACH ROW IS
  BEGIN
     NULL;
  END AFTER EACH ROW;

  AFTER STATEMENT IS
  BEGIN
   IF USER = 'DELIUS_AUDIT_DMS_POOL'
     THEN
        EXECUTE IMMEDIATE 'ALTER SESSION SET nls_date_format = ''YYYY-MM-DD HH24:MI:SS''';
        EXECUTE IMMEDIATE 'ALTER SESSION SET nls_timestamp_format = ''YYYY-MM-DD HH24:MI:SS.FF9''';
     END IF;
  END AFTER STATEMENT;

END;
/

EXIT
EOSQL