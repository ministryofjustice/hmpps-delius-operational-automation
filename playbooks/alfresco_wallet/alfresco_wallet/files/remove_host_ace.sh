#!/bin/bash
#
#  Remove ACEs for the previous Alfresco Host
#  If the last ACE is removed for this host then the ACL will automatically drop
#
. ~oracle/.bash_profile

sqlplus -s /  as sysdba <<EOF
SET LINES 1000
SET PAGES 0
SET FEEDBACK OFF
SET HEADING OFF
WHENEVER SQLERROR EXIT FAILURE


BEGIN
  FOR x IN (SELECT lower_port,upper_port,principal,privilege
            FROM   dba_host_aces
            WHERE  host = '${PREV_ALFRESCO_HOST}')
  LOOP
      DBMS_NETWORK_ACL_ADMIN.remove_host_ace (
        host             => '${PREV_ALFRESCO_HOST}', 
        lower_port       => x.lower_port,
        upper_port       => x.upper_port,
        ace              => xs\$ace_type(privilege_list => xs\$name_list(x.privilege),
                                         principal_name => x.principal,
                                         principal_type => xs_acl.ptype_db),
        remove_empty_acl => TRUE); 
  END LOOP;
END;
/

EXIT
EOF