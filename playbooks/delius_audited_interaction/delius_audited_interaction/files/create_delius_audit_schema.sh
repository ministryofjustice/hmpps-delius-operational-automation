#!/bin/bash
#
#  Create the DELIUS_AUDIT_SCHEMA Schema Only Account
#  (No connections are made directly to this schema - all connections are through the DELIUS_AUDIT_POOL account)

#  NB:  This schema is installed into ALL Delius Databases - both the Clients and Repository

. ~/.bash_profile

sqlplus /nolog <<EOSQL
connect / as sysdba

WHENEVER SQLERROR EXIT FAILURE

CREATE USER delius_audit_schema NO AUTHENTICATION
DEFAULT TABLESPACE t_audint_data;

ALTER USER delius_audit_schema QUOTA UNLIMITED ON t_audint_data;

-- Set up schema objects for DELIUS_AUDIT_SCHEMA

ALTER SESSION SET CURRENT_SCHEMA=delius_audit_schema;

-- Table for Logging Oldest Uncommitted Transaction Dates When Capture was Last Run (Lower Bound on Potential Audit Data Load)
  CREATE TABLE audit_capture
   (	
      client_db VARCHAR2(20) PRIMARY KEY, 
	   oldest_tx_last_capture DATE
   );

GRANT SELECT, INSERT, UPDATE ON audit_capture TO delius_audit_pool; 

-- Create Staging Tables for Data Fetch

CREATE TABLE stage_audited_interaction
AS SELECT *
FROM delius_app_schema.audited_interaction
WHERE 1=2;

CREATE TABLE stage_user_
AS SELECT *
FROM delius_app_schema.user_
WHERE 1=2;

CREATE TABLE stage_probation_area_user
AS SELECT *
FROM delius_app_schema.probation_area_user
WHERE 1=2;

GRANT SELECT, INSERT ON stage_audited_interaction TO delius_audit_pool;
GRANT SELECT, INSERT ON stage_user_ TO delius_audit_pool;
GRANT SELECT, INSERT ON stage_probation_area_user TO delius_audit_pool;

CREATE OR REPLACE PACKAGE truncate_staging_tables
AS
   PROCEDURE stage_audited_interaction;
   PROCEDURE stage_user_;
   PROCEDURE stage_probation_area_user;
END truncate_staging_tables;
/

CREATE OR REPLACE PACKAGE BODY truncate_staging_tables
AS

   PROCEDURE stage_audited_interaction
   AS
   BEGIN
      EXECUTE IMMEDIATE 'TRUNCATE TABLE stage_audited_interaction';
   END stage_audited_interaction;

   PROCEDURE stage_user_
   AS
   BEGIN
      EXECUTE IMMEDIATE 'TRUNCATE TABLE stage_user_';
   END stage_user_;

   PROCEDURE stage_probation_area_user
   AS
   BEGIN
      EXECUTE IMMEDIATE 'TRUNCATE TABLE stage_probation_area_user';
   END stage_probation_area_user;

END truncate_staging_tables;
/

GRANT EXECUTE ON truncate_staging_tables TO delius_audit_pool;

GRANT SELECT, INSERT ON delius_app_schema.audited_interaction TO delius_audit_pool;
GRANT SELECT, INSERT, UPDATE ON delius_app_schema.user_ TO delius_audit_pool;
GRANT SELECT, INSERT ON delius_app_schema.probation_area_user TO delius_audit_pool;
GRANT SELECT ON delius_app_schema.business_interaction TO delius_audit_pool;
GRANT SELECT ON delius_app_schema.probation_area TO delius_audit_pool;

-- Set up synonyms for DELIUS_AUDIT_POOL

ALTER SESSION SET CURRENT_SCHEMA=delius_audit_pool;

CREATE OR REPLACE SYNONYM audit_capture FOR delius_audit_schema.audit_capture;
CREATE OR REPLACE SYNONYM stage_audited_interaction FOR delius_audit_schema.stage_audited_interaction;
CREATE OR REPLACE SYNONYM stage_user_ FOR delius_audit_schema.stage_user_;
CREATE OR REPLACE SYNONYM stage_probation_area_user FOR delius_audit_schema.stage_probation_area_user;

CREATE OR REPLACE SYNONYM audited_interaction FOR delius_app_schema.audited_interaction;
CREATE OR REPLACE SYNONYM user_ FOR delius_app_schema.user_;
CREATE OR REPLACE SYNONYM probation_area_user FOR delius_app_schema.probation_area_user;
CREATE OR REPLACE SYNONYM probation_area FOR delius_app_schema.probation_area;

-- Utilities
CREATE OR REPLACE SYNONYM truncate_staging_tables FOR delius_audit_schema.truncate_staging_tables;

EXIT
EOSQL