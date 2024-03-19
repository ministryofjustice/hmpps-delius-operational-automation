#!/bin/bash
. ~/.bash_profile
SOURCE_DB=$1
CATALOG_DB=$2
RESTORE_DATETIME=${3:-NONE}
DATEFORMAT='YYMMDDHH24MISS'

. /etc/environment
SSMNAME="/${HMPPS_ENVIRONMENT}/${APPLICATION}/oracle-db-operation/rman/rman_password"
RMANPASS=`aws ssm get-parameters --region ${REGION} --with-decryption --name ${SSMNAME} | jq -r '.Parameters[].Value'`
if [ -z ${RMANPASS} ]
then
  echo "Password for rman in aws parameter store ${SSMNAME} does not exist"
  exit 1
fi
CATALOG_CONNECT=rman19c/${RMANPASS}@${CATALOG_DB}

if [ "${RESTORE_DATETIME}" != "NONE" ]
then

sqlplus -s ${CATALOG_CONNECT} << EOF
whenever sqlerror exit failure
set feedback off heading off pages 0 verify off echo off
col c format 9
select trim(count(*)) c
from (select min(decode(btyp,'FULL',btim,null)) full_time
            ,max(decode(btyp,'ARCH',btim,null))	arch_time
        from (select 'FULL' btyp
                     ,btim
                from (select min(bp.completion_time) btim
                      from rc_database d
                         ,rc_backup_piece bp
                      where bp.db_key = d.db_key
                      and bp.backup_type in ('D','I')
                      and d.name = upper('${SOURCE_DB}')
                      and bp.incremental_level = 0)
              union
              select 'ARCH' btyp
                    ,btim
                from (select max(bp.completion_time) btim
                        from rc_database d
                            ,rc_backup_piece bp
                        where bp.db_key = d.db_key
                        and bp.backup_type = 'L'
                        and d.name = upper('${SOURCE_DB}'))
        )
     )
where full_time <= to_date('${RESTORE_DATETIME}','${DATEFORMAT}')
and   arch_time >= to_date('${RESTORE_DATETIME}','${DATEFORMAT}')
/
EOF

fi