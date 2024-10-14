#!/bin/bash
#
#  Create the DELIUS_AUDIT_DMS_POOL Schema in the account which should already exist
#
#  (Ideally we should have a separate schema for this but AWS DMS cannot DELETE from
#  other schemas and will only try to TRUNCATE which causes a privilege error.   Rather
#  than granting DROP ANY TABLE which is extreme overkill, it is preferred to just
#  use a single schema - POOL).

#  NB:  This schema is installed into ALL Delius Databases - both the Clients and Repository

. ~/.bash_profile

sqlplus /nolog <<EOSQL
connect / as sysdba

SET ECHO ON
SET VERIFY ON

WHENEVER SQLERROR EXIT FAILURE

ALTER USER delius_audit_dms_pool QUOTA UNLIMITED ON t_audint_data;

-- Set up schema objects for DELIUS_AUDIT_DMS_POOL

ALTER SESSION SET CURRENT_SCHEMA=delius_audit_dms_pool;

CREATE TABLE stage_business_interaction 
   ( business_interaction_id   NUMBER       NOT NULL, 
	  business_interaction_code VARCHAR2(20) NOT NULL, 
	  enabled_date              DATE, 
	  client_db                 VARCHAR2(30) NOT NULL,
      CONSTRAINT pk_stage_business_interaction PRIMARY KEY (client_db, business_interaction_id)
   ) 
  ORGANIZATION INDEX
  TABLESPACE t_audint_data
  PARTITION BY LIST (client_db) 
 ( PARTITION others  VALUES (DEFAULT)  TABLESPACE t_audint_data );

COMMENT ON TABLE stage_business_interaction IS 'Copy of current state of BUSINESS_INTERACTION tables in all Client Databases';

CREATE TABLE audited_interaction_checksum
   ( client_db           VARCHAR2(30) NOT NULL,
     start_date_time     DATE NOT NULL,
     resetlogs           CHAR(1),
     end_date_time       DATE NOT NULL,
     row_count           NUMBER(38) NOT NULL,
     data_checksum       NUMBER(38) NOT NULL,
     checksum_validated  CHAR(1),
     CONSTRAINT pk_audited_interaction_checksum PRIMARY KEY (client_db, start_date_time, end_date_time)
   )
   ORGANIZATION INDEX
   TABLESPACE t_audint_data
   PARTITION BY LIST (client_db)
  ( PARTITION others  VALUES (DEFAULT)  TABLESPACE t_audint_data );

COMMENT ON TABLE audited_interaction_checksum IS 'Checksum for Audited Interaction Data for all Client Databases';

/*
   For DELIUS_APP_SCHEMA tables Supplementary Logging is enabled as part of DMS Setup.
   However, this table is different since it is in the DELIUS_AUDIT_DMS_POOL schema and
   hence does not exist at DMS Setup.   Therefore we add the Supplemental Logging
   directly to the table.
*/
ALTER TABLE audited_interaction_checksum ADD SUPPLEMENTAL LOG DATA (PRIMARY KEY) COLUMNS;

/*
 The environment variable DATABASE_NAMES contains a CSV list of all
 Delius database names configured.  Loop through these and create
 partitions/sub-partitions for each within the staging and checksum tables.
*/
PROMPT "Adding staging partitions for ${DATABASE_NAMES}"

DECLARE
    l_csv_list   VARCHAR2(4000) := '${DATABASE_NAMES}'; -- CSV List of All Database Names
    l_value      VARCHAR2(4000);
    l_position   INTEGER;
BEGIN
    LOOP
        -- Find the first comma
        l_position := INSTR(l_csv_list, ',');

        -- If there's a comma, extract the value, else get the whole string
        IF l_position > 0 THEN
            l_value := SUBSTR(l_csv_list, 1, l_position - 1);
            l_csv_list := SUBSTR(l_csv_list, l_position + 1);
        ELSE
            l_value := l_csv_list;
            l_csv_list := NULL;
        END IF;

        /*
            For each database name we add:
              - Partitions to the STAGE_BUSINESS_INTERACTION table
              - Partitions to the AUDITED_INTERACTION_CHECKSUM table

            Not all databases will be in use so some partitions will remain
            empty but they do not take up space due to deferred segment
            creation.
        */        
        EXECUTE IMMEDIATE 'ALTER TABLE stage_business_interaction SPLIT PARTITION others INTO (PARTITION '||l_value||
                          ' VALUES ('''||l_value||'''), PARTITION others)';

        EXECUTE IMMEDIATE 'ALTER TABLE audited_interaction_checksum SPLIT PARTITION others INTO (PARTITION '||l_value||
                          ' VALUES ('''||l_value||'''), PARTITION others)';

        EXIT WHEN l_csv_list IS NULL OR l_csv_list = '';
    END LOOP;
END;
/

CREATE OR REPLACE SYNONYM audited_interaction FOR delius_app_schema.audited_interaction;
CREATE OR REPLACE SYNONYM business_interaction FOR delius_app_schema.business_interaction;

GRANT SELECT,INSERT ON delius_app_schema.audited_interaction TO delius_audit_dms_pool;
GRANT SELECT,INSERT ON delius_app_schema.business_interaction TO delius_audit_dms_pool;

GRANT SELECT,INSERT,DELETE ON stage_business_interaction TO delius_audit_dms_pool;

-- Note that we require the DELETE privilege since DMS will attempt to delete rows immediately
-- prior to inserting them (even if they do not already exist) and will fail if this
-- permission is not available.
GRANT SELECT,INSERT,UPDATE,DELETE ON delius_app_schema.user_ TO delius_audit_dms_pool;
GRANT SELECT,INSERT,UPDATE,DELETE ON delius_app_schema.probation_area_user TO delius_audit_dms_pool;

/*
   The following view is used to handle DMS insert attempts into the AUDITED_INTERACTION
   table.  These will be incoming without a populated CLIENT_BUSINESS_INTERACT_CODE,
   since this cannot be joined to the BUSINESS_INTERACTION table by DMS (Joins not
   supported).   Therefore we create a view with an INSTEAD OF trigger to allow the
   data to be joined to the staged BUSINESS_INTERACTION look-up.
*/

CREATE OR REPLACE VIEW dms_audited_interaction
AS
    SELECT
        ai.date_time,
        ai.outcome,
        ai.interaction_parameters,
        ai.user_id,
        ai.business_interaction_id,
        ai.spg_username,
        ai.client_db,
        ai.client_business_interact_code
    FROM
        delius_app_schema.audited_interaction              ai
        LEFT JOIN delius_audit_dms_pool.stage_business_interaction bi 
    ON ai.business_interaction_id = bi.business_interaction_id
    AND ai.client_db = bi.client_db
    WHERE
        ai.client_db IS NOT NULL;

CREATE OR REPLACE FUNCTION get_business_interaction_code (
    p_business_interaction_id stage_business_interaction.business_interaction_id%TYPE,
    p_client_db               stage_business_interaction.client_db%TYPE
) RETURN stage_business_interaction.business_interaction_code%TYPE
    RESULT_CACHE
AS
    l_business_interaction_code stage_business_interaction.business_interaction_code%TYPE;
BEGIN
    SELECT
        business_interaction_code
    INTO l_business_interaction_code
    FROM
        stage_business_interaction
    WHERE
            business_interaction_id = p_business_interaction_id
        AND client_db = client_db;

    RETURN l_business_interaction_code;
EXCEPTION
    WHEN no_data_found THEN
        RETURN NULL;
END get_business_interaction_code;
/


CREATE OR REPLACE TRIGGER instead_of_audited_interaction 
INSTEAD OF
    INSERT ON dms_audited_interaction
    FOR EACH ROW
BEGIN
    INSERT INTO delius_app_schema.audited_interaction (
        date_time,
        outcome,
        interaction_parameters,
        user_id,
        business_interaction_id,
        spg_username,
        client_db,
        client_business_interact_code
    ) VALUES (
        :new.date_time,
        :new.outcome,
        :new.interaction_parameters,
        :new.user_id,
        :new.business_interaction_id,
        :new.spg_username,
        :new.client_db,
        get_business_interaction_code(
            p_business_interaction_id => :new.business_interaction_id, 
            p_client_db => :new.client_db
        )
    );
END;
/

CREATE OR REPLACE PACKAGE pkg_checksum 
AS
   /*
       This package provides a data checksum facility for data written
       to AUDITED_INTERACTION over a particular time period.
       It allows the checksum in the Client Database to be compared to
       that in the Repository Database to provide a quick reassurance
       that all Audit Data is being successfully replicated.

       The Checksum is not a mandatory part of Audited Interaction
       Data Preservation but is an additional data integrity check.
    */
    
    -- If p_final is TRUE we are taking a final checksum before removing
    -- the database:  in this case include all data up to the current time.
    PROCEDURE calculate_new_checksum(p_final BOOLEAN DEFAULT FALSE);
    
    PROCEDURE validate_checksums;
END pkg_checksum;
/

CREATE OR REPLACE PACKAGE BODY pkg_checksum 
AS
    /*
        The calculate_new_checksum procedure is used by client
        databases to calculate a new checksum for all audit
        records created since the previous checksum.
    */
    PROCEDURE calculate_new_checksum(p_final BOOLEAN DEFAULT FALSE)
    AS
      l_client_database  VARCHAR2(30);
      l_resetlogs_date   DATE;
      l_date_range_start DATE;
      l_date_range_end   DATE;
      l_resetlogs        CHAR(1) := 'N';
    BEGIN

      SELECT global_name
      INTO   l_client_database
      FROM   global_name;

      SELECT resetlogs_time
      INTO   l_resetlogs_date
      FROM   v\$database;

      /*
         We calculate the checksum across all rows since the latest
         previous checksum.   Note that this means that some rows
         which fall precisely on the start/end date_time will be
         included in both previous and new checksums.
         However, this does not cause any problems, other than the
         total row count over ALL checksums may not accurately reflect
         the total row count of all audit data.

         We only check for checksums in the current incarnation
         (more recent than the latest RESETLOGS).   If there is
         no checksum for the current incarnation then use the
         RESETLOGS time as the range start date.
      */
      SELECT COALESCE(MAX(end_date_time),l_resetlogs_date)
      INTO   l_date_range_start
      FROM   audited_interaction_checksum
      WHERE  client_db = l_client_database
      AND    start_date_time >= l_resetlogs_date;

      /*
         The end time for the checksum is the earliest uncommitted
         transaction (in case that contains audit records) or else
         the current time minus one hour if there are no active transactions.
         (We allow an hours grace for audit records to be inserted
          so that the checksum is not replicated before the required
          audit records).
         Because the date time resolution is only to the nearest
         second, we subtract 1 second from the range end time to
         avoid complications due to overlap.
      */
      SELECT LEAST(COALESCE(MIN(TO_DATE(start_time,'MM/DD/RR HH24:MI:SS')),SYSDATE-(1/24)),SYSDATE-(1/24))-(1/24/60/60)
      INTO   l_date_range_end
      FROM   v\$transaction;

      -- If this is a final checksum before removing the database then
      -- it should include all data to the current time.
      IF p_final THEN
         l_date_range_end := SYSDATE;
      END IF;      

      -- Do not allow the end date to be earlier than the start date.
      -- This is unlikely to happen but is possible if run too frequently.
      l_date_range_end := GREATEST(l_date_range_start,l_date_range_end);

      /*
          If the start date has been reset to the RESETLOGS date
          then flag this as a RESETLOGs so that we can
          avoid reporting on a discontinuity in the monitoring.
      */
      IF l_date_range_start = l_resetlogs_date
      THEN
         l_resetlogs := 'Y';
      END IF;

      INSERT INTO audited_interaction_checksum
      (client_db, start_date_time, end_date_time, resetlogs, row_count, data_checksum)
      SELECT l_client_database
            ,l_date_range_start
            ,l_date_range_end
            ,l_resetlogs
            ,COUNT(*)
            ,COALESCE(SUM(ORA_HASH(TO_CHAR(ai.date_time,'YYYYMMDDHH24MISS')||
                   ai.outcome||ai.interaction_parameters||
                   ai.user_id||ai.business_interaction_id)),0)
      FROM  audited_interaction ai
      WHERE date_time BETWEEN l_date_range_start AND l_date_range_end;

   END calculate_new_checksum;
   
   /*
       The validate_checksums procedure is used by repository databases
       to compare the received checksums from the client database with
       the received audit data from the client database.
       
       This is based on the CHECKSUM_VALIDATED column in the
       AUDITED_INTERACTION_CHECKSUM table which takes the following values:
       
       NULL - used on client database only (no validation takes place on client)
       N    - newly received checksum which has not been validated
       Y    - checksum has been successfully validated against received audit data
       E    - error: checksum or row count was not successfully validated
    */
   PROCEDURE validate_checksums
   AS
      l_row_count   audited_interaction_checksum.row_count%TYPE;
      l_checksum    audited_interaction_checksum.data_checksum%TYPE;
      l_validated   audited_interaction_checksum.checksum_validated%TYPE;
   BEGIN
   
      FOR x IN (SELECT aic.*, aic.rowid row_id
                FROM   audited_interaction_checksum aic
                WHERE  checksum_validated = 'N')
      LOOP
          SELECT  COUNT(*) row_count
                 ,COALESCE(SUM(ora_hash(to_char(ai.date_time, 'YYYYMMDDHH24MISS')
                             || ai.outcome
                             || ai.interaction_parameters
                             || ai.user_id
                             || ai.business_interaction_id)),0)
          INTO  l_row_count
               ,l_checksum
          FROM  delius_app_schema.audited_interaction ai
          WHERE ai.client_db = x.client_db
          AND   ai.date_time BETWEEN x.start_date_time AND x.end_date_time;
          
          IF  l_row_count = x.row_count
          AND l_checksum  = x.data_checksum
          THEN
              l_validated := 'Y';
          ELSE
              l_validated := 'E';
          END IF;
          
          UPDATE audited_interaction_checksum
          SET    checksum_validated = l_validated
          WHERE  ROWID = x.row_id;
          
          IF SQL%ROWCOUNT != 1 
          THEN
             RAISE_APPLICATION_ERROR(-20780,'Failed to set validation status for '||x.client_db);
          END IF;
          
      END LOOP;
      
   END validate_checksums;
    
END pkg_checksum;
/

/*
    We use DBMS_SCHEDULER to periodically update the Audited Interaction
    Data Checksum
*/
BEGIN
    DBMS_SCHEDULER.CREATE_SCHEDULE(
        schedule_name   => 'AUDIT_CHECKSUM_CALCULATE_SCHEDULE',
        start_date      => SYSTIMESTAMP,
        repeat_interval => 'FREQ=HOURLY; INTERVAL=6',
        comments        => 'Calculate Audited Interaction Checksum'
    );
END;
/

/*
   The scheduler job for calculating the Checksum is initially disabled
   as we only wish to enable it for Client Databases and not 
   for Repository Databases.
*/
BEGIN
    DBMS_SCHEDULER.CREATE_JOB(
        job_name        => 'AUDIT_CHECKSUM_CALCULATE_JOB',
        job_type        => 'PLSQL_BLOCK',
        job_action      => 'BEGIN PKG_CHECKSUM.calculate_new_checksum; END;',
        schedule_name   => 'DELIUS_AUDIT_DMS_POOL.AUDIT_CHECKSUM_CALCULATE_SCHEDULE',
        enabled         => FALSE
    );
END;
/


/*
    We use DBMS_SCHEDULER to periodically validate recieved checksums
*/
BEGIN
    DBMS_SCHEDULER.CREATE_SCHEDULE(
        schedule_name   => 'AUDIT_CHECKSUM_VALIDATE_SCHEDULE',
        start_date      => SYSTIMESTAMP,
        repeat_interval => 'FREQ=HOURLY; INTERVAL=1',
        comments        => 'Validate All Received Audited Interaction Checksums'
    );
END;
/

/*
   The scheduler job for validating the received Checksums is initially disabled
   as we only wish to enable it for Repository Databases and not 
   for Client Databases.
*/
BEGIN
    DBMS_SCHEDULER.CREATE_JOB(
        job_name        => 'AUDIT_CHECKSUM_VALIDATE_JOB',
        job_type        => 'PLSQL_BLOCK',
        job_action      => 'BEGIN PKG_CHECKSUM.validate_checksums; END;',
        schedule_name   => 'DELIUS_AUDIT_DMS_POOL.AUDIT_CHECKSUM_VALIDATE_SCHEDULE',
        enabled         => FALSE
    );
END;
/


/*
   DMS creates its own operational tables under the DELIUS_AUDIT_DMS_POOL schema.
   Ensure this account has quota to write to them in the defalt tablespace.
*/

COL default_tablespace NEW_VALUE QUOTA_REQUIRED

SELECT default_tablespace
FROM   dba_users
WHERE  username = 'DELIUS_AUDIT_DMS_POOL';

ALTER USER delius_audit_dms_pool QUOTA 10G on &&QUOTA_REQUIRED;

EXIT
EOSQL