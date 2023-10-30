#!/bin/bash
#
#  Create ACE for DELIUS_APP_SCHEMA to use HTTPS for connection to Alfresco URL
#
. ~oracle/.bash_profile

sqlplus -s /  as sysdba <<EOF
SET LINES 1000
SET PAGES 0
SET FEEDBACK OFF
SET HEADING OFF
WHENEVER SQLERROR EXIT FAILURE

BEGIN
   -- Enable HTTPS Access from DELIUS_APP_SCHEMA to Alfresco Host
   DBMS_NETWORK_ACL_ADMIN.append_host_ace (
    host       => '${ALFRESCO_HOST}', 
    lower_port => 443,
    upper_port => 443,
    ace        => xs\$ace_type(privilege_list => xs\$name_list('http'),
                               principal_name => 'DELIUS_APP_SCHEMA',
                               principal_type => xs_acl.ptype_db)); 
END;
/

EXIT
EOF