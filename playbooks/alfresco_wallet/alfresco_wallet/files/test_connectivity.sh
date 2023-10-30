#!/bin/bash
#  
# Check connection to Alresco works by making a request and checking
# for a response.  No valid data should be returned as the request
# is not well formed, but it is sufficient to check that the
# connection can be established.

. ~/.bash_profile
sqlplus -s / as sysdba <<EOF
WHENEVER SQLERROR EXIT FAILURE;
SET FEEDBACK OFF
SET HEADING OFF
SET SERVEROUT ON
SET NEWPAGE 0
SET PAGESIZE 0

ALTER SESSION SET CURRENT_SCHEMA=delius_app_schema;

SET SERVEROUT ON

DECLARE
  l_url             spg_control.value_string%TYPE;  
  l_wallet_location spg_control.value_string%TYPE;       
  l_http_request    UTL_HTTP.req;
  l_http_response   UTL_HTTP.resp;
  l_text            VARCHAR2(32767);
BEGIN


  SELECT   value_string
  INTO     l_wallet_location
  FROM     spg_control
  WHERE    control_code = 'ALFWALLET';

  UTL_HTTP.set_wallet(l_wallet_location, NULL);

  SELECT    value_string
  INTO      l_url
  FROM      spg_control
  WHERE     control_code = 'ALFURL';

  -- Make a HTTP request and get the response.
  l_http_request  := UTL_HTTP.begin_request(l_url);

  l_http_response := UTL_HTTP.get_response(l_http_request);

  -- Loop through the response.
  BEGIN
    LOOP
      UTL_HTTP.read_text(l_http_response, l_text, 32766);
      DBMS_OUTPUT.put_line (l_text);
    END LOOP;
  EXCEPTION
    WHEN UTL_HTTP.end_of_body THEN
      UTL_HTTP.end_response(l_http_response);
  END;
EXCEPTION
  WHEN OTHERS THEN
    UTL_HTTP.end_response(l_http_response);
    RAISE;
END;
/
exit
EOF