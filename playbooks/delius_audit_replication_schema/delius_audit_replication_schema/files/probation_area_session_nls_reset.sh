. ~/.bash_profile

sqlplus /nolog <<EOSQL
connect / as sysdba

WHENEVER SQLERROR EXIT FAILURE;

SET SERVEROUT ON

CREATE OR REPLACE TRIGGER delius_user_support.audit_control_on_probation_area_user
FOR delete OR update OR insert ON delius_app_schema.user_
COMPOUND TRIGGER

  BEFORE STATEMENT IS
  BEGIN
     NULL;
  END BEFORE STATEMENT;

  BEFORE EACH ROW IS
  BEGIN
     IF USER = 'DELIUS_AUDIT_DMS_POOL'
     THEN
        /*
           AWS DMS uses a hard-coded date and timestamp format which differs from the
           one used by Delius itself.  Whenever the PROBATION_AREA_USER table is updated, a trigger
           fires for MIS CDC capture which sets the session date format to the
           Delius one (YYYYMMDD HH24:MI:SS).   This will cause DMS to fail, so for
           the DELIUS_AUDIT_DMS_POOL session *only* which is used by DMS, we must reset
           to the expected DMS format (YYYY-MM-DD HH24:MI:SS) both before and after
           any DML on this table.
        */
        EXECUTE IMMEDIATE 'ALTER SESSION SET nls_date_format = ''YYYY-MM-DD HH24:MI:SS''';
        EXECUTE IMMEDIATE 'ALTER SESSION SET nls_timestamp_format = ''YYYY-MM-DD HH24:MI:SS.FF9''';
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
        /*
           The session NLS values will have been changed by a Delius trigger on PROBATION_AREA_USER
           so if this is a DMS session we need to reset them back to their expected
           values.
        */
        EXECUTE IMMEDIATE 'ALTER SESSION SET nls_date_format = ''YYYY-MM-DD HH24:MI:SS''';
        EXECUTE IMMEDIATE 'ALTER SESSION SET nls_timestamp_format = ''YYYY-MM-DD HH24:MI:SS.FF9''';
     END IF;
  END AFTER STATEMENT;

END;
/

EXIT
EOSQL