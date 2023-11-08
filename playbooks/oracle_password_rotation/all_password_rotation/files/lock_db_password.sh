#!/bin/bash
#
#  Lock Database Password
#

. ~/.bash_profile

[[ ! -z ${DB_NAME} ]] && CONNECT="@${DB_NAME}"
[[ -z ${LOGIN_USER} ]] && SYSDBA="as sysdba"

sqlplus -S /nolog <<EOSQL
connect ${LOGIN_USER}/${LOGIN_PWD}${CONNECT} ${SYSDBA}
set trimspool on
set pages 0
set lines 30
set feedback off
whenever sqlerror exit failure

SET SERVEROUT ON

DECLARE
  l_lock_required INTEGER;
BEGIN
    SELECT COUNT(*) lock_required
    INTO   l_lock_required
    FROM   dba_users
    WHERE  username = '${DB_USERNAME}'
    AND    account_status = 'OPEN';

    IF l_lock_required > 0
    THEN
       EXECUTE IMMEDIATE 'ALTER USER ${DB_USERNAME} ACCOUNT LOCK';
       DBMS_OUTPUT.put_line('Locked ${DB_USERNAME}');
    END IF;
END;
/

exit;
EOSQL
