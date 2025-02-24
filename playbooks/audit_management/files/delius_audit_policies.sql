WHENEVER SQLERROR EXIT FAILURE
SET SERVEROUTPUT ON SIZE UNLIMITED
SET VERIFY OFF 

-- These policies are based on recommendations in the Oracle Database Unified Audit: Best Practice Guidelines 
-- and the hrpdb_scripts referenced on p38 
-- https://www.oracle.com/docs/tech/dbsec/unified-audit-best-practice-guidelines.pdf
--

/* **** */
/* Enable Oracle pre-defined audit piolicies */
/* **** */

prompt --Monitor common security relevant activities

AUDIT POLICY ORA_SECURECONFIG;

AUDIT POLICY ORA_ACCOUNT_MGMT;

--Monitor common suspicious activities
prompt --Monitor multiple failed login attempts
-- By default it should only audit when not successful.
AUDIT POLICY ORA_LOGON_FAILURES WHENEVER NOT SUCCESSFUL;

prompt --Audit that the Center for Internet Security (CIS) recommends.
AUDIT POLICY ORA_CIS_RECOMMENDATIONS;

/* **** */
/* Custom audit policies */
/* **** */

-- Superfluous records for COMMIT where being added to the audit trail when using ACTIONS ALL.
-- Can't use EXCLUDE with ACTIONS ALL so need to specify each action.
-- Use SYS_SESSION_ROLES to check DBA role as USERENV.ISDBA wasn't picking up <username>_DBA users as DBAs.
CREATE AUDIT POLICY all_dba_actions 
ACTIONS
ALTER CLUSTER,CREATE CLUSTER,DROP CLUSTER,TRUNCATE CLUSTER,
ALTER FUNCTION,CREATE FUNCTION,DROP FUNCTION,
ALTER INDEX,CREATE INDEX,DROP INDEX,
ALTER OUTLINE,CREATE OUTLINE,DROP OUTLINE,
ALTER PACKAGE,CREATE PACKAGE,DROP PACKAGE,
ALTER PACKAGE BODY,CREATE PACKAGE BODY,DROP PACKAGE BODY,
ALTER SEQUENCE,CREATE SEQUENCE,DROP SEQUENCE,
ALTER TABLE,CREATE TABLE,DROP TABLE,TRUNCATE TABLE,
ALTER TRIGGER,CREATE TRIGGER,DROP TRIGGER,
ALTER TYPE,CREATE TYPE,DROP TYPE,
ALTER TYPE BODY,CREATE TYPE BODY,DROP TYPE BODY,
ALTER VIEW,CREATE VIEW,DROP VIEW,
DELETE, INSERT, UPDATE
WHEN 'SYS_CONTEXT(''SYS_SESSION_ROLES'',''DBA'') = ''TRUE'''
EVALUATE PER SESSION
ONLY TOPLEVEL;

AUDIT POLICY all_dba_actions;

prompt --Audit same as original traditional audit policy
-- Have removed LOGON as we don't need to capture every single successful login for all accounts and failures are captured by ORA_LOGON_FAILURES.
-- Logon auditing is convered by pre-defined ORA_LOGON_FAILURES policy (above) and delius_logon (below).
CREATE AUDIT POLICY delius
PRIVILEGES
        CREATE EXTERNAL JOB,
        CREATE ANY JOB,
        GRANT ANY OBJECT PRIVILEGE,
        CREATE ANY LIBRARY,
        GRANT ANY PRIVILEGE,
        DROP PROFILE,
        ALTER PROFILE,
        DROP ANY PROCEDURE,
        ALTER ANY PROCEDURE,
        CREATE ANY PROCEDURE,
        ALTER DATABASE,
        GRANT ANY ROLE,
        CREATE PUBLIC DATABASE LINK,
        DROP ANY TABLE,
        ALTER ANY TABLE,
        CREATE ANY TABLE,
        DROP USER,
        ALTER USER,
        BECOME USER,
        CREATE USER,
        AUDIT SYSTEM,
        ALTER SYSTEM,
        CREATE EXTERNAL JOB,
        CREATE PUBLIC SYNONYM,
        DROP PUBLIC SYNONYM
ACTIONS 
        CREATE DATABASE LINK,
        ALTER DATABASE LINK,
        DROP DATABASE LINK,
        CREATE ROLE,
        ALTER ROLE,
        DROP ROLE,
        SET ROLE,
        CREATE PROFILE,
        ALTER PROFILE,
        DROP PROFILE,
        CREATE DIRECTORY,
        DROP DIRECTORY,
        GRANT,
        REVOKE,
        CREATE PLUGGABLE DATABASE,
        ALTER PLUGGABLE DATABASE,
        DROP PLUGGABLE DATABASE,
        CHANGE PASSWORD
ONLY TOPLEVEL;

AUDIT POLICY delius;

-- create a separate policy for logon auditing so we can exlcude those from the DMS pool
CREATE AUDIT POLICY delius_logon
PRIVILEGES
        CREATE SESSION
ACTIONS 
        LOGON
ONLY TOPLEVEL;

AUDIT POLICY delius_logon EXCEPT DELIUS_AUDIT_DMS_POOL;
-- See this article for details about DMS implementation https://dsdmoj.atlassian.net/wiki/spaces/DSTT/pages/5195465768/AWS+DMS+For+Delius+Audit+Preservation
-- There is no way to tune the DMS connection pool.

prompt --Audit database-management events
CREATE AUDIT POLICY TABLESPACE_CHANGES
ACTIONS
CREATE TABLESPACE, ALTER TABLESPACE, DROP TABLESPACE
ONLY TOPLEVEL;

AUDIT POLICY TABLESPACE_CHANGES;

--To verify the audit policies configured:
--select *
--from AUDIT_UNIFIED_ENABLED_POLICIES

