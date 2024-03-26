#!/bin/bash

. ~/.bash_profile

DB_USER="SYS\$UMF"
DB_PASS=$(aws secretsmanager get-secret-value --secret-id ${SECRET_ID} --query SecretString --output text | jq -r .sysumf)

sqlplus -s / as sysdba << EOF

SET LINES 132
SET PAGES 0
SET FEEDBACK OFF
SET HEADING OFF
WHENEVER SQLERROR EXIT FAILURE;

DECLARE

    l_adg_db_unique_name        v\$archive_dest_status.db_unique_name%TYPE;
    l_primary_db_unique_name    v\$archive_dest_status.db_unique_name%TYPE;

    FUNCTION db_link_exists (p_db_link VARCHAR2) RETURN BOOLEAN
    IS
    l_count NUMBER(1);
    BEGIN

        SELECT COUNT(*)
        INTO l_count
        FROM dba_db_links
        WHERE db_link = p_db_link;

        IF l_count = 0
        THEN
            RETURN FALSE;
        ELSE
            RETURN TRUE;
        END IF;

    END db_link_exists;
    --
    PROCEDURE create_db_link (p_db_link VARCHAR2, p_db_unique_name VARCHAR2)
    IS
    l_sql   VARCHAR2(1000);
    BEGIN

        IF NOT db_link_exists (p_db_link)
        THEN
            l_sql := 'CREATE DATABASE LINK '||p_db_link||
                     ' CONNECT TO ${DB_USER} IDENTIFIED BY "${DB_PASS}" USING '||
                     ''''||p_db_unique_name||'''';

            EXECUTE IMMEDIATE l_sql;
        END IF;

    END create_db_link;
    --
BEGIN

    SELECT UPPER(db_unique_name)
    INTO l_primary_db_unique_name
    FROM v\$archive_dest_status
    WHERE database_mode = 'OPEN'
    AND type = 'LOCAL';

    SELECT UPPER(db_unique_name)
    INTO l_adg_db_unique_name
    FROM v\$archive_dest_status
    WHERE database_mode IN ('OPEN_READ-ONLY')
    AND type = 'PHYSICAL'
    AND status = 'VALID';

    create_db_link('${PRIMARY_DB_LINK}', l_adg_db_unique_name);
    create_db_link('${ADG_DB_LINK}', l_primary_db_unique_name);

END;    
/
EXIT
EOF