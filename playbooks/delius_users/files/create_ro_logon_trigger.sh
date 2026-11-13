#!/bin/bash
#
#  Any user with the suffix _RO is a read only user and should be using
#  the DELIUS_APP_SCHEMA by default.   This trigger ensures the schema is
#  setup appropriately.   The trigger is in the DELIUS_USER_SUPPORT schema
#  rather than the users own schema in order to prevent it from being
#  accidentally dropped.

. ~/.bash_profile

sqlplus -s / as sysdba << EOF

WHENEVER SQLERROR EXIT FAILURE;

CREATE OR REPLACE TRIGGER delius_user_support.${RO_USER}
AFTER LOGON ON ${RO_USER}.SCHEMA
BEGIN
   EXECUTE IMMEDIATE 'ALTER SESSION SET CURRENT_SCHEMA=DELIUS_APP_SCHEMA';
END;
/

SELECT CASE
         WHEN created = last_ddl_time THEN 'Trigger was created.'
         ELSE 'Trigger was replaced.'
       END AS trigger_status
  FROM dba_objects
 WHERE object_type   = 'TRIGGER'
   AND owner  = 'DELIUS_USER_SUPPORT'
   AND object_name   = '${RO_USER}';

EXIT
EOF