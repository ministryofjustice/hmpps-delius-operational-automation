#!/bin/bash

. ~/.bash_profile

PATH=$PATH:/usr/local/bin
ORAENV_ASK=NO
ORACLE_SID=${CATALOG_DB}
. oraenv > /dev/null 2>&1
RMANPASS=$(aws secretsmanager get-secret-value --secret-id "/oracle/database/${CATALOG_DB}/shared-passwords" --query SecretString --output text | jq -r .rcvcatowner)

sqlplus -s /  as sysdba <<EOF
SET LINES 1000
SET PAGES 0
SET FEEDBACK OFF
SET HEADING OFF
WHENEVER SQLERROR EXIT FAILURE

DECLARE

l_count         NUMBER(1);

BEGIN

    SELECT COUNT(*)
    INTO l_count
    FROM dba_users
    WHERE username = '${NEW_CATALOG_SCHEMA}';

    IF l_count > 0
    THEN
        EXECUTE IMMEDIATE 'DROP USER ${NEW_CATALOG_SCHEMA} CASCADE';
    END IF;
    
    SELECT COUNT(*)
    INTO l_count
    FROM dba_tablespaces
    WHERE tablespace_name = 'RCVCAT_${SOURCE_CATALOG_DB}_TBS';

    IF l_count < 1
    THEN
        EXECUTE IMMEDIATE q'[CREATE TABLESPACE RCVCAT_${SOURCE_CATALOG_DB}_TBS DATAFILE '+DATA' SIZE 1G AUTOEXTEND ON MAXSIZE UNLIMITED]';
    END IF;
    
END;
/
EOF