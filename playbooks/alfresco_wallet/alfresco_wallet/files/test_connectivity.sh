#!/bin/bash
#  
# Check connection to Alresco works by making a request and checking
# for a response.  No valid data should be returned as the request
# is not well formed, but it is sufficient to check that the
# connection can be established.

INSTANCEID=$(wget -q -O - http://169.254.169.254/latest/meta-data/instance-id)
ENVIRONMENT_NAME=$(aws ec2 describe-tags --filters "Name=resource-id,Values=${INSTANCEID}" "Name=key,Values=environment-name"  --query "Tags[].Value" --output text)
DELIUS_ENVIRONMENT=$(aws ec2 describe-tags --filters "Name=resource-id,Values=${INSTANCEID}" "Name=key,Values=delius-environment"  --query "Tags[].Value" --output text)
SECRET_ID=${ENVIRONMENT_NAME%-*}-${DELIUS_ENVIRONMENT}-oracle-db-application-passwords
DELIUS_APP_SCHEMA_PASSWORD=$(aws secretsmanager get-secret-value --secret-id ${SECRET_ID} --query SecretString --output text| jq -r .delius_app_schema)

. ~/.bash_profile
sqlplus -s /nolog <<EOF

-- Test using DELIUS_APP_SCHEMA user as this requires the ACL Setup
connect DELIUS_APP_SCHEMA/${DELIUS_APP_SCHEMA_PASSWORD}

WHENEVER SQLERROR EXIT FAILURE;
SET FEEDBACK OFF
SET HEADING OFF
SET SERVEROUT ON
SET NEWPAGE 0
SET PAGESIZE 0
SET LINES 2000

ALTER SESSION SET CURRENT_SCHEMA=delius_app_schema;

SET SERVEROUT ON

DECLARE
    l_url             spg_control.value_string%TYPE;
    l_base_url        VARCHAR2(4000);
    l_probe_url       VARCHAR2(4000);
    l_wallet_location spg_control.value_string%TYPE;
    l_http_request    utl_http.req;
    l_http_response   utl_http.resp;
    l_text            VARCHAR2(32767);
    l_scheme_end      PLS_INTEGER;
    l_path_start      PLS_INTEGER;
    c_probe_path      CONSTANT VARCHAR2(200) := '/alfresco/api/-default-/public/alfresco/versions/1/probes/-live-';
BEGIN
    SELECT
        value_string
    INTO l_wallet_location
    FROM
        spg_control
    WHERE
        control_code = 'ALFWALLET';

    utl_http.set_wallet(l_wallet_location, NULL);
    SELECT
        value_string
    INTO l_url
    FROM
        spg_control
    WHERE
        control_code = 'ALFURL';

    -- Strip URL to base (scheme + host) e.g. https://host.example.com
    l_scheme_end := INSTR(l_url, '://');
    IF l_scheme_end > 0 THEN
        l_path_start := INSTR(l_url, '/', l_scheme_end + 3);
        IF l_path_start > 0 THEN
            l_base_url := SUBSTR(l_url, 1, l_path_start - 1);
        ELSE
            l_base_url := l_url;
        END IF;
    ELSE
        l_base_url := l_url;
    END IF;

    l_probe_url := l_base_url || c_probe_path;

    -- Make HTTP request to the liveness probe endpoint
    l_http_request := utl_http.begin_request(l_probe_url);
    l_http_response := utl_http.get_response(l_http_request);

    -- Check for HTTP 200
    IF l_http_response.status_code != 200 THEN
        utl_http.end_response(l_http_response);
        dbms_output.put_line('FAIL|Liveness probe returned HTTP ' || l_http_response.status_code || ' (expected 200)');
        RETURN;
    END IF;

    -- Read response body and check for "Success"
    BEGIN
        utl_http.read_text(l_http_response, l_text, 32767);
    EXCEPTION
        WHEN utl_http.end_of_body THEN
            NULL;
    END;
    utl_http.end_response(l_http_response);

    IF INSTR(l_text, 'Success') > 0 THEN
        dbms_output.put_line('SUCCESS|Liveness probe OK: ' || l_text);
    ELSE
        dbms_output.put_line('FAIL|Liveness probe response did not contain Success: ' || SUBSTR(l_text, 1, 500));
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        BEGIN
            utl_http.end_response(l_http_response);
        EXCEPTION
            WHEN OTHERS THEN NULL;
        END;
        dbms_output.put_line(SUBSTR(translate('FAIL|' || dbms_utility.format_error_stack, '|'
                                                                                   || chr(10)
                                                                                   || chr(13), '|  '),1,1000));

END;
/
EOF