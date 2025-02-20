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

AUDIT POLICY ORA_LOGON_FAILURES;

/* **** */
/* Custom audit policies */
/* **** */

CREATE AUDIT POLICY all_dba_actions
ACTIONS ALL
WHEN 'SYS_CONTEXT(''USERENV'',''ISDBA'') = ''TRUE'''
EVALUATE PER STATEMENT
ONLY TOPLEVEL;

AUDIT POLICY all_dba_actions;

prompt --Audit same as original traditional audit policy
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
        CREATE SESSION,
        AUDIT SYSTEM,
        ALTER SYSTEM,
        CREATE EXTERNAL JOB,
        CREATE PUBLIC SYNONYM,
        DROP PUBLIC SYNONYM
ACTIONS 
        LOGON,
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
        DROP PLUGGABLE DATABASE
ONLY TOPLEVEL;

AUDIT POLICY DELIUS;


prompt --Audit database-management events
CREATE AUDIT POLICY TABLESPACE_CHANGES
ACTIONS
CREATE TABLESPACE, ALTER TABLESPACE, DROP TABLESPACE
ONLY TOPLEVEL;

AUDIT POLICY TABLESPACE_CHANGES;

--To verify the audit policies configured:
--select *
--from AUDIT_UNIFIED_ENABLED_POLICIES

