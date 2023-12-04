#!/bin/bash

. ~/.bash_profile

sqlplus -s / as sysdba << EOF

SET LINES 132
SET PAGES 0
SET FEEDBACK OFF
SET HEADING OFF
WHENEVER SQLERROR EXIT FAILURE;

DECLARE

l_umf_remote_enabled     x\$ksppsv.ksppstvl%TYPE;

BEGIN

    SELECT c.ksppstvl inv
    INTO l_umf_remote_enabled
    FROM    x\$ksppi a,
            x\$ksppcv b,
            x\$ksppsv c
    WHERE  a.indx = b.indx
    AND    a.indx = c.indx
    AND    UPPER(a.ksppinm) = '_UMF_REMOTE_ENABLED';
    --
    IF l_umf_remote_enabled = 'FALSE'
    THEN
        EXECUTE IMMEDIATE 'ALTER SYSTEM SET "_umf_remote_enabled"=TRUE SCOPE=BOTH';
    END IF;
    --
END;
/
EXIT
EOF