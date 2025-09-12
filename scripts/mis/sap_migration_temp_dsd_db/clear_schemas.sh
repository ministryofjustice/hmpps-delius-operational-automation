#!/bin/bash

if [[ "$ORACLE_SID" != "DMDDXB" ]];
then
	echo "Wrong Database!"
	exit 1
fi

sqlplus / as sysdba <<EOSQL

SELECT COUNT(*)
FROM   dba_objects
where owner in ('DFI_IPSAUD','DFI_IPSCMS','IPSAUD','IPSCMS');

BEGIN
FOR x IN (
   select 'DROP '||object_type||' '||owner||'.'||object_name||(CASE WHEN object_type = 'TABLE' THEN ' CASCADE CONSTRAINTS' ELSE NULL END) dropcmd
   from dba_objects
   where owner in ('DFI_IPSAUD','DFI_IPSCMS','IPSAUD','IPSCMS')
   and object_type not in ('INDEX','LOB'))
LOOP
   EXECUTE IMMEDIATE x.dropcmd;
END LOOP;
END;
/

SELECT COUNT(*)
FROM   dba_objects
where owner in ('DFI_IPSAUD','DFI_IPSCMS','IPSAUD','IPSCMS');

EXIT
EOSQL