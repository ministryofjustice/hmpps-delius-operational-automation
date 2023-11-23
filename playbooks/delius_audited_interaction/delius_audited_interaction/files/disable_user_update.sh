#  After a database has been duplicated, the Users table should no longer be updateable by the Delius Application
. ~/.bash_profile

sqlplus /nolog <<EOSQL
connect / as sysdba

WHENEVER SQLERROR EXIT FAILURE;

SET SERVEROUT ON

-- Revoke any privileges will allow any user to modify the USERS_ table
-- (This is an additional precaution; trigger should be sufficient)
-- DELIUS_AUDIT_POOL is still allowed to add new Service Users
BEGIN
FOR x IN (SELECT grantee,privilege
          FROM   dba_tab_privs
          WHERE  owner = 'DELIUS_APP_SCHEMA'
          AND    table_name = 'USER_'
          AND    grantee != 'DELIUS_AUDIT_POOL'
          AND    privilege IN ('DELETE','UPDATE','INSERT'))
LOOP
  EXECUTE IMMEDIATE 'REVOKE '||x.privilege||' ON DELIUS_APP_SCHEMA.USER_ FROM '||x.grantee;
  DBMS_OUTPUT.put_line('Revoked '||x.privilege||' on USER_ from '||x.grantee);
END LOOP;
END;
/

-- Additionally we add a trigger to enforce the same restrictions for the Application Schema itself
-- (This is an additional precaution; read only should be sufficient)
CREATE OR REPLACE TRIGGER delius_user_support.audit_control_on_user_
BEFORE delete OR update OR insert ON delius_app_schema.user_
FOR EACH ROW
BEGIN
  IF UPDATING('USER_ID') OR UPDATING('DISTINGUISHED_NAME') OR UPDATING('SURNAME')
  OR UPDATING('FORENAME') OR UPDATING('FORENAME2')
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
  -- Service and Stub Users may be added but only by the DELIUS_AUDIT_POOL User running the Service User Loader.
  -- Such users are being propagated from production.
  -- Service Users are identified by IDs of less than 10,000,000
  IF INSERTING
  AND NOT (USER = 'DELIUS_AUDIT_POOL' 
           AND SYS_CONTEXT('userenv', 'client_identifier') = 'SERVICE_USER_LOADER' 
           AND ((:new.user_id < 10000000) OR (:new.notes LIKE 'This is a Stub Record%')))
  THEN
      RAISE_APPLICATION_ERROR(-20923,'To allow for audit trail consistency no new users (except Service and Stub users) may be added in this environment.');
  END IF;
  IF DELETING
  THEN
      RAISE_APPLICATION_ERROR(-20924,'To allow for audit trail consistency no users may be deleted in this environment.');
  END IF;
  IF UPDATING
  THEN
     -- If any UPDATEs occur then do not allow them to move the LAST_UPDATED_DATETIME as this is used to detect any 
     -- more recent data changes in the production environment
     :new.last_updated_datetime := :old.last_updated_datetime;
  END IF;
END;
/

EXIT
EOSQL