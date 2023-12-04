#!/bin/bash
# Lock or Unlock Database Accounts
# This is to avoid any accidental application access to the database during the upgrade.

ACCOUNTSTATE=$1

. ~/.bash_profile

sqlplus /nolog <<EOSQL
WHENEVER SQLERROR EXIT FAILURE
connect / as sysdba
BEGIN
   FOR u IN (SELECT username
             FROM   dba_users
             WHERE  username IN ('DELIUS_POOL','GDPR_POOL','DELIUS_APP_SCHEMA','DELIUS_APP_SCRIPTS','DELIUS_CFO','DELIUS_MIS','DELIUS_READ_ONLY_USER','DELIUS_USERSHARE_SCHEMA','DELIUS_USER_SUPPORT')
             OR     username IN ('NDMIS_DATA','MIS_LANDING','NDMIS_ARC','NDMIS_CDC_SUBSCRIBER','NDMIS_FORMS_2030','NDMIS_LOADER','NDMIS_WORKING')
             OR     username IN ('B14AUD','B14CMS')
             OR     username IN ('IPSAUD','IPSCMS','BODSLOCAL','BODSCENTRAL')) LOOP
   EXECUTE IMMEDIATE 'ALTER USER '||u.username||' ACCOUNT ${ACCOUNTSTATE}';
   END LOOP;
END;
/
EOSQL

