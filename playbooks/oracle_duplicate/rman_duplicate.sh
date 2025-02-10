#!/bin/bash

typeset -u RUN_MODE
export RUN_MODE=LIVE

typeset -u DEBUG_MODE
export DEBUG_MODE=N

export THISSCRIPT=`basename $0`
export THISDIRECTORY=`dirname $0`
export THISHOST=`uname -n`
typeset -u CATALOG_DB
typeset -u TARGET_DB
typeset -u SOURCE_DB

export TIMESTAMP=`date +"%Y%m%d%H%M"`
export RMANDATEFORMAT='YYMMDDHH24MISS';
export RMANDUPLICATELOGFILE=/home/oracle/admin/rman_scripts/rman_duplicate_${TIMESTAMP}.log
export RMANDUPLICATECMDFILE=/home/oracle/admin/rman_scripts/rman_duplicate.cmd

export SUCCESS_STATUS=0
export WARNING_STATUS=1
export ERROR_STATUS=9

#
#  If the restore datetime is not specified then we look up the highest SCN for backed up
#  archive logs in the RMAN catalog and use that.   NB: if no target date or SCN is
#  specified for the RMAN duplicate command will attempt to use the highest SCN for all
#  archive logs in the catalog regardless of whether these have been backed up or not, so
#  this should be avoided as, if they are not backed up, the duplicate may fail.
#
usage () {
  echo ""
  echo "Usage:"
  echo ""
  echo "  $THISSCRIPT -d <target db> -s <source db> -c <catalog db> -u <catalog schema> -t <restore datetime> [ -f <spfile parameters> ] [-l] [-n]"
  echo ""
  echo "where"
  echo ""
  echo "  target db         = target database to clone to"
  echo "  source db         = source database to clone from"
  echo "  catalog db        = rman repository"
  echo "  catalog schema    = rman schema"
  echo "  restore datetime  = optional date time of production backup to restore from"
  echo "                      format [YYMMDDHH24MISS]"
  echo "  spfile parameters = extra spfile set parameters"
  echo "  -l                = use local disk backup only (do not allocate sbt channels)"
  echo ""
  echo "  If -r is specified then a repository must be specified for sending GitHub actions repository dispatch events."
  echo "      This would typically be ministryofjustice/hmpps-delius-operational-automation and is used for triggering"
  echo "      any follow-on GitHub actions necessary upon succesful or unsuccessful completion."
  echo "  "
  echo "  If -j is specified then it should be followed by a valid JSON string representing all of the inputs to the GitHub"
  echo "       backup workflow.  This is used to supply the original input parameters back to the GitHub workflow in the case"
  echo "       that we wish to continue the workflow after this script has finished running. This parameter is mandatory"
  echo "       if -r is used to specify the use of repository dispatch events."
  echo ""
  echo "  If -n is specified (no argument accepted) then the duplicate is done as a no-op.  This skips the actual"
  echo "        RMAN duplicate script run, and a success code is returned.  No-op mode is intended primarily for"
  echo "        development purposes where we wish to avoid the lengthy runtime involved in running an RMAN duplicate."
  echo ""
  echo "  If -o is specified then the duplicate is from legacy. Depending on the option value the appropriate action is taken."
  echo "        option value:"
  echo "           duplicate: RMAN duplicate command using source target"
  echo "           restore: RMAN duplicate command for standby recover only"
  echo "           recover: RMAN recover command (and possible restore command for additional datafiles added at source)"
  echo "           open: RMAN recover command and convert standby database to primary"
  echo ""

  exit $ERROR_STATUS
}

function generate_jwt()
{
# Get a JSON Web Token to authenicate against the HMPPS Bot.
# The HMPPS bot can provide exchange this for a GitHub Token for action GitHub workflows.
BOT_APP_ID=$(aws ssm get-parameter --name "/github/hmpps_bot_app_id" --query "Parameter.Value" --with-decryption --output text)
BOT_PRIVATE_KEY=$(aws ssm get-parameter --name "/github/hmpps_bot_priv_key" --query "Parameter.Value" --with-decryption --output text)

# Define expiry time for JWT - we will be using it immediately so just use a 10 minute expiry time.
NOW=$(date +%s)
INITIAL=$((${NOW} - 60)) # Issues 60 seconds in the past (avoid time jitter problem)
EXPIRY=$((${NOW} + 600)) # Expires 10 minutes in the future

# This function is used to apply Base64 encoding for the token to allow it to be passed on.
b64enc() { openssl base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n'; }

# The JWT requires a Header, Payload and Signature as defined here.
HEADER_JSON='{
    "typ":"JWT",
    "alg":"RS256"
}'
# Header encode
HEADER=$( echo -n "${HEADER_JSON}" | b64enc )

PAYLOAD_JSON='{
    "iat":'"${INITIAL}"',
    "exp":'"${EXPIRY}"',
    "iss":'"${BOT_APP_ID}"'
}'
# Payload encode in Base64
PAYLOAD=$( echo -n "${PAYLOAD_JSON}" | b64enc )

# Signature
HEADER_PAYLOAD="${HEADER}"."${PAYLOAD}"
SIGNATURE=$(
    openssl dgst -sha256 -sign <(echo -n "${BOT_PRIVATE_KEY}") \
    <(echo -n "${HEADER_PAYLOAD}") | b64enc
)

# Create JWT
JWT="${HEADER_PAYLOAD}"."${SIGNATURE}"
printf '%s\n' "$JWT"
}

function get_github_token()
{
# Generate JSON Web Token to authenticate to HMPPS Bot
JWT=$(generate_jwt)
# Fetch Installation ID for App in target Repository
BOT_INSTALL_ID=$(aws ssm get-parameter --name "/github/hmpps_bot_installation_id" --query "Parameter.Value" --with-decryption --output text)
GITHUB_TOKEN=$(curl --request POST --url "https://api.github.com/app/installations/${BOT_INSTALL_ID}/access_tokens" --header "Accept: application/vnd.github+json" --header "Authorization: Bearer $JWT" --header "X-GitHub-Api-Version: 2022-11-28")
printf '%s\n' "$GITHUB_TOKEN"
}

function github_repository_dispatch()
{
# Because this script is intended to run asynchronously and may be called by a GitHub Workflow, we use
# GitHub Repository Dispatch events to call back to the Workflow to allow it to continue.  This is a 
# workaround to avoid two issues:
# (1) Timeout of GitHub actions lasting over 6 hours.
# (2) Billing costs associated with the GitHub hosted runner actively waiting whilst the backup runs.
#
# We supply 2 parameters to this function:
#  EVENT_TYPE is a user-defined event to pass to the GitHub repository.   The duplicate worflow is triggered
#  for either ooracle-rman-duplicate-sucess or oracle-rman-duplicate-failure events.   These are the only 2 which
#  should be used.
#  JSON_PAYLOAD is the JSON originally passed to the script using the -j switch.  This allows the
#  workflow to continue where it left off because this JSON contains the name of the environment, host
#  and period of the backup, along with any associated parameters.
EVENT_TYPE=$1
JSON_PAYLOAD=$(echo $2 | jq -r)
GITHUB_TOKEN_VALUE=$(get_github_token | jq -r '.token')
# We set the Phase in the JSON payload corresponding to whether the backup has succeeded or failed.
# This is informational only - it is GitHub event type (oracle-rman-duplicate-success/failure) which 
# determines what the workflow does next.
if [[ "$EVENT_TYPE" == "oracle-rman-duplicate-success" ]]; then
    JSON_PAYLOAD=$(echo $JSON_PAYLOAD | jq -r '.Phase = "Duplicate Succeeded"')
else
    JSON_PAYLOAD=$(echo $JSON_PAYLOAD | jq -r '.Phase = "Duplicate Failed"')
fi
JSON_DATA="{\"event_type\": \"${EVENT_TYPE}\",\"client_payload\":${JSON_PAYLOAD}}"
info "Posting repository dispatch event"
curl -X POST -H "Accept: application/vnd.github+json" -H "Authorization: token ${GITHUB_TOKEN_VALUE}"  --data-raw "${JSON_DATA}" ${REPOSITORY_DISPATCH}
RC=$?
if [[ $RC -ne 0 ]]; then
      # We cannot use the error function for dispatch failures as it contains its own dispatch call   
      T=`date +"%D %T"`
      echo "ERROR : $THISSCRIPT : $T : Failed to dispatch ${EVENT_TYPE} event to ${REPOSITORY_DISPATCH}"
      exit 1
fi
}

info () {
  T=`date +"%D %T"`
  echo "INFO : $THISSCRIPT : $T : $1"
  if [ "$DEBUG_MODE" = "Y" ]
  then
    read CONTINUE?"Press any key to continue "
  fi
}

warning () {
  T=`date +"%D %T"`
  echo "WARNING : $THISSCRIPT : $T : $1"
}

error () {
  T=`date +"%D %T"`
  echo "ERROR : $THISSCRIPT : $T : $1"
  [[ ! -z "$REPOSITORY_DISPATCH" ]] && github_repository_dispatch "oracle-rman-duplicate-failure" "${JSON_INPUTS}"
  exit $ERROR_STATUS
}

set_ora_env () {
  export ORAENV_ASK=NO
  export ORACLE_SID=$1
  . oraenv
  unset SQLPATH
  unset TWO_TASK
  unset LD_LIBRARY_PATH
  export NLS_DATE_FORMAT=YYMMDDHH24MI
}

get_catalog_connection () {
  # Determine the rman password depending where the catalog database resides
  if [[ ! ${CATALOG_DB} =~ ^\(DESCRIPTION.* ]]
  then
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${OEM_SECRET_ROLE}"
    SESSION="catalog-ansible"
    SECRET_ACCOUNT_ID=$(aws ssm get-parameters --with-decryption --name account_ids | jq -r .Parameters[].Value |  jq -r 'with_entries(if (.key|test("hmpps-oem.*$")) then ( {key: .key, value: .value}) else empty end)' | jq -r 'to_entries|.[0].value' )
    CREDS=$(aws sts assume-role --role-arn "${ROLE_ARN}" --role-session-name "${SESSION}"  --output text --query "Credentials.[AccessKeyId,SecretAccessKey,SessionToken]")
    export AWS_ACCESS_KEY_ID=$(echo "${CREDS}" | tail -1 | cut -f1)
    export AWS_SECRET_ACCESS_KEY=$(echo "${CREDS}" | tail -1 | cut -f2)
    export AWS_SESSION_TOKEN=$(echo "${CREDS}" | tail -1 | cut -f3)
    SECRET_ARN="arn:aws:secretsmanager:eu-west-2:${SECRET_ACCOUNT_ID}:secret:/oracle/database/${CATALOG_DB}/shared-passwords"
    RMANUSER=${CATALOG_SCHEMA:-rcvcatowner}
    RMANPASS=$(aws secretsmanager get-secret-value --secret-id "${SECRET_ARN}" --query SecretString --output text | jq -r .rcvcatowner)
    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
  else
    INSTANCE_ID=$(curl http://169.254.169.254/latest/meta-data/instance-id)
    APPLICATION=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$INSTANCE_ID" "Name=key,Values=application" --query 'Tags[0].Value' --output text)
    RMANUSER=rman19c
    if [ "$APPLICATION" = "delius" ]
    then
      SECRET_ID="${ENVIRONMENT_NAME}-oracle-db-dba-passwords"
    elif [ "$APPLICATION" = "delius-mis" ]
    then
      DATABASE_TYPE=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$INSTANCE_ID" "Name=key,Values=database" --query 'Tags[0].Value' --output text | cut -d'_' -f1)
      SECRET_ID="${ENVIRONMENT_NAME}-oracle-${DATABASE_TYPE}-db-dba-passwords"
    fi
    RMANPASS=$(aws secretsmanager get-secret-value --secret-id ${SECRET_ID} --query SecretString --output text | jq -r .rman)
  fi
  [ -z ${RMANPASS} ] && error "Password for rman catalog does not exist"
  CATALOG_CONNECT=${RMANUSER}/${RMANPASS}@"${CATALOG_DB}"
  CONNECT_TO_CATALOG=$(echo "connect catalog $CATALOG_CONNECT;")
}

validate () {
  ACTION=$1
  case "$ACTION" in
       user) info "Validating user"
             THISUSER=`id | cut -d\( -f2 | cut -d\) -f1`
             [ "$THISUSER" != "oracle" ] && error "Must be oracle to run this script"
             info "User ok"
             ;;
   targetdb) info "Validating target database"
             [ -z "$TARGET_DB" -o "$TARGET_DB" = "UNSPECIFIED" ] && usage
             grep ^${TARGET_DB}: /etc/oratab >/dev/null 2>&1 || error "Database $TARGET_DB does not exist on this machine"
             info "Target database ok"
             info "Set environment for $TARGET_DB"
             set_ora_env $TARGET_DB
             ;;
    catalog) info "Validating catalog database"
             if [ -z $CATALOG_DB ]
             then
               error "Catalog not specified, please specify catalog db"
             else
               get_catalog_connection
             fi
             info "Catalog ok"
             ;;
   datetime) info "Validating restore datetime format"
             if [ "${DATETIME}" != "LATEST" ]
             then
               X=`sqlplus -s ${CATALOG_CONNECT} << EOF
                  whenever sqlerror exit 1
                  set feedback off heading off verify off echo off
                  select to_date('${DATETIME}','${RMANDATEFORMAT}') from dual;
                  exit
EOF
` || error "Restore datetime ${DATETIME} format incorrect"
             fi
             ;;
          *) error "Incorrect parameter passed to vaidate function"
             ;;
  esac
}

remove_asm_directory () {
  VG=$1
  TARGETDB=$2
  sleep 10
  ORAENV_ASK=NO
  ORACLE_SID=+ASM
  . oraenv
  info "Remove directory ${TARGETDB} in ${VG} volume group"
  if asmcmd ls +${VG}/${TARGETDB} > /dev/null 2>&1
  then
     asmcmd rm -rf +${VG}/${TARGETDB} || error "Removing directory ${TARGETDB} in ${VG}/${TARGETDB}"
  else
    info "No asm directory in ${VG} to delete"
  fi
}

get_source_db_rman_details () {

  X=`sqlplus -s ${CATALOG_CONNECT} <<EOF
      whenever sqlerror exit failure
      set feedback off heading off verify off echo off

      with completion_times as
        (select a.dbid,
                decode(b.bck_type,'D',max(b.completion_time)) full_time,
                decode(b.bck_type,'I',max(b.completion_time)) incr_time,
                decode(b.bck_type,'L',max(b.completion_time)) arch_time,
                max(d.next_time)                              arch_next_time,
                max(d.next_change#)                           arch_scn
          from rc_database a,
               bs b,
               rc_database_incarnation c,
               rc_backup_archivelog_details d
          where a.name = '$SOURCE_DB'
          and a.db_key=b.db_key
          and a.db_key=c.db_key
          and a.dbinc_key = c.dbinc_key
          and b.bck_type is not null
          and b.bs_key not in (select bs_key
                              from rc_backup_controlfile
                              where autobackup_date is not null
                              or autobackup_sequence is not null)
          and b.bs_key not in (select bs_key
                              from  rc_backup_spfile)
          and b.db_key=d.db_key(+)
          and d.btype(+) = 'BACKUPSET'
          and b.bs_key=d.btype_key(+)
          group by a.dbid,b.bck_type)
      select 'DBID='||dbid,
             'FULL_TIME='||''''||to_char(max(full_time),'${RMANDATEFORMAT}')||'''',
             'INCR_TIME='||''''||to_char(max(incr_time),'${RMANDATEFORMAT}')||'''',
             'ARCH_TIME='||''''||to_char(max(arch_time),'${RMANDATEFORMAT}')||'''',
             'NEXT_TIME='||''''||to_char(max(arch_next_time),'${RMANDATEFORMAT}')||'''',
             'SCN='||to_char(max(arch_scn))
      from completion_times
      group by dbid
      order by max(incr_time) desc
      fetch first 1 rows only;
EOF
`
  eval $X || error "Getting $SOURCE_DB rman details"
  info "${SOURCE_DB} dbid = ${DBID}"
  if [ "${DATETIME}" = "LATEST" ]
  then
    info "Restore time = ${NEXT_TIME}"
    info "Restore SCN  = ${SCN}"
  else
    info "Restore time = ${DATETIME}"
  fi
}

get_new_data_files () {
  V_DATABASE=v\$database
  X=`sqlplus -s "/ as sysdba" <<EOF
      whenever sqlerror exit failure
      set feedback off heading off verify off echo off
      select 'CURRENT_SCN="'||current_scn||'"'
      from $V_DATABASE
      where controlfile_type = 'STANDBY';
EOF
`
  eval $X || error "Getting current scn from target scn"
  [[ -z "${CURRENT_SCN}" ]] && error "Current scn is empty, please check if controlfile type of ${TARGET_DB} database is STANDBY"

  Y=`sqlplus -s ${CATALOG_CONNECT} <<EOF
      whenever sqlerror exit failure
      set feedback off heading off verify off echo off
      select 'NEW_DATAFILES="'||listagg(distinct(file#),' ')||'"'
      from rc_database a,
           rc_backup_datafile b,
           rc_database_incarnation c
      where a.name = '${SOURCE_DB}'
      and a.db_key = b.db_key
      and a.db_key = c.db_key
      and a.dbinc_key = c.dbinc_key
      and c.current_incarnation = 'YES'
      and b.creation_change# between ${CURRENT_SCN} and ${SCN};
EOF
`
  eval $Y || error "Getting rman new datafiles details"
  [[ ! -z "${NEW_DATAFILES}" ]] && info "New datafile file# since last recovery = ${NEW_DATAFILES}"
}

build_rman_command_file () {

  V_PARAMETER=v\$parameter
  X=`sqlplus -s "/ as sysdba" <<EOF
     whenever sqlerror exit 1
     set feedback off heading off verify off echo off
     select 'CPU_COUNT="'||value||'"' from $V_PARAMETER
     where name = 'cpu_count';
     exit
EOF
` || "Cannot determine cpu count"
  eval $X
  info "cpu count = $CPU_COUNT"

  >$RMANDUPLICATECMDFILE
  if [[ "${LEGACY_OPTION}" =~ ^(recover|open)$ ]]
  then
    ALLOCATE_CHANNEL="allocate channel"
    CONNECT_TYPE="connect target /"
  else
    ALLOCATE_CHANNEL="allocate auxiliary channel"
    CONNECT_TYPE="connect auxiliary /"
  fi
  echo "run {" >>$RMANDUPLICATECMDFILE
  TYPE="sbt\n  parms='SBT_LIBRARY=${ORACLE_HOME}/lib/libosbws.so,\n  ENV=(OSB_WS_PFILE=${THISDIRECTORY}/osbws_duplicate.ora)';"
  for (( i=1; i<=${CPU_COUNT}; i++ ))
  do
    if [[ "${LOCAL_DISK_BACKUP}" == "TRUE" ]]
    then
       echo -e "  ${ALLOCATE_CHANNEL} c${i} device type DISK;" >> $RMANDUPLICATECMDFILE
    else
       echo -e "  ${ALLOCATE_CHANNEL} c${i} device type $TYPE" >> $RMANDUPLICATECMDFILE
    fi
  done
  get_source_db_rman_details
  if [[ "${LEGACY_OPTION}" =~ ^(recover|open)$ ]]
  then
    echo "  set until scn ${SCN};" >> $RMANDUPLICATECMDFILE
    get_new_data_files
    if [[ ! -z "${NEW_DATAFILES}" ]]
    then
      for i in ${NEW_DATAFILES}
      do
        echo "  set newname for datafile $i to '+DATA';" >> $RMANDUPLICATECMDFILE
        echo "  restore datafile $i;" >> $RMANDUPLICATECMDFILE
      done
      echo "  switch datafile all;" >> $RMANDUPLICATECMDFILE
    fi
    echo "  recover database;" >> $RMANDUPLICATECMDFILE
    if [[ "${LEGACY_OPTION}" = "open" ]]
    then
      echo '  sql "alter database activate standby database";' >> $RMANDUPLICATECMDFILE
      echo '  sql "alter database open";' >> $RMANDUPLICATECMDFILE
      echo "  host 'srvctl modify database -d ${TARGET_DB} -startoption OPEN';" >> $RMANDUPLICATECMDFILE
      echo "  host 'srvctl modify database -d ${TARGET_DB} -role PRIMARY';" >> $RMANDUPLICATECMDFILE
    fi
    for (( i=1; i<=${CPU_COUNT}; i++ ))
    do
      echo -e "  release channel c${i};" >> $RMANDUPLICATECMDFILE
    done
    echo "}" >>$RMANDUPLICATECMDFILE
    return 0
  fi
  echo "  duplicate database ${SOURCE_DB} dbid ${DBID} "  >> $RMANDUPLICATECMDFILE
  if [[ "${LEGACY_OPTION}" == "restore" ]]
  then
    echo "  for standby dorecover" >> $RMANDUPLICATECMDFILE
  else
    echo "  to ${TARGET_DB}" >> $RMANDUPLICATECMDFILE
  fi
  echo "  spfile " >> $RMANDUPLICATECMDFILE
  # No need to set spfile convert parameters if source and target databases are the same
  if [[ "${source_db}" != "${target_db}" ]]
  then
    echo "    parameter_value_convert ('${SOURCE_DB}','${TARGET_DB}','${source_db}','${target_db}')" >> $RMANDUPLICATECMDFILE
    echo "    set db_file_name_convert='+DATA/${SOURCE_DB}','+DATA/${TARGET_DB}'" >> $RMANDUPLICATECMDFILE
    echo "    set log_file_name_convert='+DATA/${SOURCE_DB}','+DATA/${TARGET_DB}','+FLASH/${SOURCE_DB}','+FLASH/${TARGET_DB}'" >> $RMANDUPLICATECMDFILE
  fi
  [[ "${LEGACY_OPTION}" == "restore" ]] && echo "    set db_unique_name='${TARGET_DB}'" >> $RMANDUPLICATECMDFILE
  echo "    set fal_server=''" >> $RMANDUPLICATECMDFILE
  echo "    set log_archive_config=''" >> $RMANDUPLICATECMDFILE
  echo "    set log_archive_dest_2=''" >> $RMANDUPLICATECMDFILE
  echo "    set log_archive_dest_3=''" >> $RMANDUPLICATECMDFILE
  if [ "${SPFILE_PARAMETERS}" != "UNSPECIFIED" ]
  then
    for PARAM in ${SPFILE_PARAMETERS[@]}
    do
      echo "    set ${PARAM}" >> $RMANDUPLICATECMDFILE
    done
  fi
  # Source database and target database maybe the same name. Introduce nofilenamecheck to avoid rman failures.
  if [[ "${source_db}" == "${target_db}" ]]
  then
    echo "  nofilenamecheck " >> $RMANDUPLICATECMDFILE
  fi
  if [ "${DATETIME}" != "LATEST" ]
  then
    echo "  until time \"TO_DATE('${DATETIME}','${RMANDATEFORMAT}')\";" >> $RMANDUPLICATECMDFILE
  else  
    echo "  until scn ${SCN};" >> $RMANDUPLICATECMDFILE 
  fi
  if [[ "${LEGACY_OPTION}" == "restore" ]]
  then
    echo '  sql "alter database flashback on";' >> $RMANDUPLICATECMDFILE
    echo "  host 'srvctl modify database -d ${TARGET_DB} -startoption MOUNT';" >> $RMANDUPLICATECMDFILE
    echo "  host 'srvctl modify database -d ${TARGET_DB} -role PHYSICAL_STANDBY';" >> $RMANDUPLICATECMDFILE
  fi
  echo "}" >>$RMANDUPLICATECMDFILE
  echo "exit"	>>$RMANDUPLICATECMDFILE
}

add_spfile_asm () {
  SPFILE=${ORACLE_HOME}/dbs/spfile${TARGET_DB}.ora
  PFILE=${ORACLE_HOME}/dbs/init${TARGET_DB}.ora
  ASMSPFILE=+DATA/${TARGET_DB}/spfile${TARGET_DB}.ora

  info "Update pfile to point to spfile in ASM"
  echo "SPFILE='${ASMSPFILE}'" > ${PFILE}

  info "Restart database using asm spfile"
  TARGET_DB_STATUS=$(srvctl status database -d ${TARGET_DB})
  if [[ ${TARGET_DB_STATUS} =~ 'Database is running' ]]
  then
    srvctl stop database -d ${TARGET_DB} || error "Stopping database ${TARGET_DB}"
  fi
  srvctl start database -d ${TARGET_DB} || error "Starting database ${TARGET_DB}"
}

enable_bct () {
  V_BLOCK_CHANGE_TRACKING=v\$block_change_tracking
  X=`sqlplus -s "/ as sysdba" <<EOF
     whenever sqlerror exit failure
     set feedback off heading off verify off echo off
     select 'STATUS="'||status||'"' from $V_BLOCK_CHANGE_TRACKING;
     exit
EOF
` || error "Cannot determine block change tracking status"
  eval $X
  info "Block Change Tracking = $STATUS"
  if [ "$STATUS" = "DISABLED" ]
  then
      if sqlplus -s / as sysdba
      then
         info "Block Change Tracking now enabled"
      else
         error "Unable to enable Block Change Tracking"
      fi <<EOSQL
         whenever sqlerror exit 1
         set feedback off heading off verify off echo off
         alter database enable block change tracking;
         exit 
EOSQL
  else
     info "Block Change Tracking is already enabled"
  fi
}

recreate_password_file () {
SYS_PASS=$1

set_ora_env +ASM
# First we must remove the old password file location from Grid Config otherwise it will not let us create a new one
srvctl modify database -d ${TARGET_DB} -pwfile
echo ${SYS_PASS} | orapwd file="+DATA/${TARGET_DB}/orapw${TARGET_DB}" dbuniquename="${TARGET_DB}"

set_ora_env ${TARGET_DB} 
}

function exists_in_list() {
    # Check if item is in list
    VALUE=$1
    DELIMITER=$2
    LIST="$3"
    DELIMITED_LIST=$(echo $LIST | tr "$DELIMITER" '\n')
    echo $VALUE | grep -F -q -x "${DELIMITED_LIST}" && echo "Found" || echo "Absent"
}

restore_db_passwords () {

  # Delius dba secret passwords are in the form of <environment-name>-oracle-db-dba-passwords
  # Mis dba secret passwords are in the form of <environment-name>-oracle-<db_type>-db-dba-passwords
  # where db_type could be either mis, dsd or boe and is pulled from database tag

  info "Looking up passwords to in aws ssm secrets to restore"
  INSTANCE_ID=$(curl http://169.254.169.254/latest/meta-data/instance-id)
  APPLICATION=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$INSTANCE_ID" "Name=key,Values=application" --query 'Tags[0].Value' --output text)
  # ENVIRONMENT_NAME=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$INSTANCE_ID" "Name=key,Values=environment-name" --query 'Tags[0].Value' --output text)
  # DELIUS_ENVIRONMENT=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$INSTANCE_ID" "Name=key,Values=delius-environment" --query 'Tags[0].Value' --output text)
  SYSTEMDBUSERS=(sys system dbsnmp)
  if [ "$APPLICATION" = "delius" ]
  then
    SECRET_PREFIX="${ENVIRONMENT_NAME}-oracle-db"
    APPLICATION_USERS=(delius_app_schema delius_pool delius_analytics_platform gdpr_pool delius_audit_dms_pool mms_pool)
    # Add Probation Integration Services by looking up the Usernames (there may be several of these)
    # We suppress any lookup errors for integration users as these may not exist
    # PROBATION_INTEGRATION_USERS=$(aws secretsmanager get-secret-value --secret-id ${ENVIRONMENT_NAME}-${DELIUS_ENVIRONMENT}-${APPLICATION}-integration-passwords --query SecretString --output text 2>/dev/null | jq -r 'keys | join(" ")')
    PROBATION_INTEGRATION_USERS=$(aws secretsmanager get-secret-value --secret-id ${ENVIRONMENT_NAME}-oracle-db-integration-passwords --query SecretString --output text 2>/dev/null | jq -r 'keys | join(" ")')
  elif [ "$APPLICATION" = "delius-mis" ]
  then
    DATABASE_TYPE=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$INSTANCE_ID" "Name=key,Values=database" --query 'Tags[0].Value' --output text | cut -d'_' -f1)
    SECRET_PREFIX="${ENVIRONMENT_NAME}-oracle-${DATABASE_TYPE}-db"
    if [[ "${DATABASE_TYPE}" == "mis" ]]
    then
      APPLICATION_USERS=(mis_landing ndmis_abc ndmis_cdc_subscriber ndmis_loader ndmis_working ndmis_data)
      APPLICATION_USERS+=(dfimis_landing dfimis_abc dfimis_subscriber dfimis_data dfimis_working dfimis_loader)
    fi
  fi
  DBUSERS+=(${APPLICATION_USERS[@]} ${PROBATION_INTEGRATION_USERS[@]} )
  #SECRET_PREFIX="${ENVIRONMENT_NAME}-${DELIUS_ENVIRONMENT}-${APPLICATION}"
  info "Change password for all db users"
  DBUSERS+=( ${SYSTEMDBUSERS[@]} )
  for USER in ${DBUSERS[@]}
  do
    # Pattern for AWS Secrets path for Probation Integration Users differs from other Oracle user accounts
    if [[ "$APPLICATION" == "delius" && $(exists_in_list "${USER}" " " "${PROBATION_INTEGRATION_USERS[*]}" ) == "Found" ]];
    then
      TYPE="integration"
    elif [[ $(exists_in_list "${USER}" " " "${APPLICATION_USERS[*]}" ) == "Found" ]];
    then
      TYPE="application"
    else
      TYPE="dba"
    fi
    SECRET_ID="${SECRET_PREFIX}-${TYPE}-passwords"
    USERPASS=$(aws secretsmanager get-secret-value --secret-id ${SECRET_ID} --query SecretString --output text | jq -r ".${USER}")
    # Ignore absense of Audit Preservation and Probation Integration Users as they may not exist in all environments
    if [[ -z ${USERPASS} && $(exists_in_list "${USER}" " " "delius_audit_pool ${PROBATION_INTEGRATION_USERS[*]}") != "Found" ]];
    then
       info "Password for $USER in AWS Secret  ${SECRET_ID} does not exist"
    fi
    if [[ -z ${USERPASS} && $(exists_in_list "${USER}" " " "delius_audit_pool ${PROBATION_INTEGRATION_USERS[*]}") == "Found" ]];
    then
       info "$USER not configured in this environment - skipping"
    else
        info "Change password for $USER"
        # Accounts may have become locked if client applications are trying to connect immediately after the database
        # is opened so we ensure that all accounts are unlocked on changing the passwords.  No error is raised if the
        # account is not already locked.
        sqlplus -s / as sysdba << EOF
        alter user $USER identified by "${USERPASS}" account unlock;
        exit
EOF
    fi
    # The Database Password File is Stored in ASM and will have been wiped by the refresh.
    # Therefore whilst we are setting the SYS password, recreate the Password File.
    if [[ "${USER}" == "sys" ]];
    then
       recreate_password_file "${USERPASS}"
    fi
  done
}

configure_rman_archive_deletion_policy () {
    rman target / << EOF > /dev/null
    CONFIGURE ARCHIVELOG DELETION POLICY TO BACKED UP 1 TIMES TO 'SBT_TAPE';
    exit
EOF

}

recreate_temporary_tablespaces () {

info "Recreate temporary tablespaces with no tempfiles"

sqlplus -s / as sysdba << EOF

declare

l_default_temporary_tablespace database_properties.property_value%type;

begin

  select property_value
  into l_default_temporary_tablespace
  from database_properties 
  where property_name = 'DEFAULT_TEMP_TABLESPACE';

  for t in (select s.name,
                  count(*) no_tempfiles
            from v\$tempfile f
            join v\$tablespace s ON s.ts# = f.ts#
            where f.name = '+DATA'
            group by s.name)
  loop

    if t.no_tempfiles > 0
    then
      if t.name = l_default_temporary_tablespace
      then
        execute immediate q'[create temporary tablespace duptemp tempfile '+data']';
        execute immediate 'alter database default temporary tablespace duptemp';
      end if;
      execute immediate 'drop tablespace '||t.name;
      for n in 1..t.no_tempfiles
      loop
        if n = 1
        then
          execute immediate 'create temporary tablespace '||t.name||q'[ tempfile '+DATA']';
        else
          execute immediate 'alter tablespace '||t.name||q'[ add tempfile '+DATA']';
        end if;
      end loop;
    end if;
    if t.name = l_default_temporary_tablespace
    then
      execute immediate 'alter database default temporary tablespace '||t.name;
      execute immediate 'drop tablespace duptemp including contents and datafiles';
    end if;
  end loop;

end;
/
exit

EOF
}

run_datapatch() {
    info "Run datapatch"
    cd ${ORACLE_HOME}/OPatch
    ./datapatch >/dev/null 2>&1
    [ $? -ne 0 ] && error "Running datapatch"
}

post_actions () {
  add_spfile_asm
  enable_bct
  restore_db_passwords
  # Ensure the archive deletion policy is set correctly for the primary database
  configure_rman_archive_deletion_policy
  # Ensure the tempfiles for temporary exist other wise recreate the temporary tablespace
  recreate_temporary_tablespaces
  # Run datapatch in case the source db is at lower release update level
  run_datapatch
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
info "Starts"
unset ORACLE_SID
info "Retrieving arguments"
[ -z "$1" ] && usage

TARGET_DB=UNSPECIFIED
DATETIME=LATEST
SPFILE_PARAMETERS=UNSPECIFIED
LEGACY_OPTION=UNSPECIFIED
while getopts "d:s:c:u:t:f:l:r:j:o:n" opt
do
  case $opt in
    d) TARGET_DB=$OPTARG ;;
    s) SOURCE_DB=$OPTARG ;;
    c) CATALOG_DB=$OPTARG ;;
    u) CATALOG_SCHEMA=$OPTARG ;;
    t) DATETIME=${OPTARG} ;;
    f) SPFILE_PARAMETERS=${OPTARG} ;;
    l) LOCAL_DISK_BACKUP=TRUE ;;
    r) REPOSITORY_DISPATCH=$OPTARG ;;
    j) JSON_INPUTS=$OPTARG ;;
    n) NOOP_MODE=TRUE ;;
    o) LEGACY_OPTION=$OPTARG ;;
    *) usage ;;
  esac
done

info "Target         = $TARGET_DB"
info "Source         = $SOURCE_DB"
info "Catalog db     = $CATALOG_DB"
info "Catalog Schema = $CATALOG_SCHEMA"
info "Restore Datetime = ${DATETIME}"
info "Legacy Option  = ${LEGACY_OPTION}"
[[ "${LOCAL_DISK_BACKUP}" == "TRUE" ]] && info "Local Disk Backup = ENABLED"
target_db=$(echo "${TARGET_DB}" | tr '[:upper:]' '[:lower:]')
source_db=$(echo "${SOURCE_DB}" | tr '[:upper:]' '[:lower:]')

validate user
info "Execute $THISUSER bash profile"
. $HOME/.bash_profile
validate targetdb
validate catalog
validate datetime

if [[ ! -z "$REPOSITORY_DISPATCH" ]]; then
   REPOSITORY_DISPATCH="https://api.github.com/repos/${REPOSITORY_DISPATCH}/dispatches"
   info "GitHub Actions Repository Dispatch Events will be sent to : $REPOSITORY_DISPATCH"
fi

if [[ ! -z "$JSON_INPUTS" ]]; then
   # The JSON Inputs are used to record the parameters originally passed to GitHub
   # actions to start the duplicate job.   These are only used for actioning a repository
   # dispatch event to indicate the end of the duplicate job run.  They do NOT
   # override the command line options passed to the script.
   JSON_INPUTS=$(echo $JSON_INPUTS | base64 --decode )
fi


if [ "${SPFILE_PARAMETERS}" != "UNSPECIFIED" ]
then
  for PARAM in ${SPFILE_PARAMETERS[@]}
  do
    if [[ ${PARAM} =~ compatible.* ]]
    then  
      COMPATIBLE=${PARAM//\'/}
    fi
  done
fi

if [[ ! "${LEGACY_OPTION}" =~ ^(recover|open)$ ]]
then
  info "Shutdown ${TARGET_DB}"
    sqlplus -s / as sysdba <<EOF
    shutdown abort;
EOF

  info "Modify database using Server Control with correct spfile location"
  srvctl modify database -d ${TARGET_DB} -p "+DATA/${TARGET_DB}/spfile${TARGET_DB}.ora"

  if [[ "${NOOP_MODE}" != "TRUE" ]];
  then
      remove_asm_directory DATA ${TARGET_DB}
      remove_asm_directory FLASH ${TARGET_DB}

      info "Create ${TARGET_DB} in +DATA in readiness for duplicate"
      asmcmd mkdir +DATA/${TARGET_DB}

      info "Set environment for ${TARGET_DB}"
      set_ora_env ${TARGET_DB}

      INI_FILES=(${ORACLE_HOME}/dbs/*${TARGET_DB}*.ora)
      if [[ -f ${INI_FILES[0]} ]]
      then
        info "Remove all references to all ${TARGET_DB} initialization files to start fresh"
        rm ${ORACLE_HOME}/dbs/*${TARGET_DB}*.ora || error "Removing ${TARGET_DB} initialization files"
      fi
  else
    info "Skipping deleting data files in noop mode"
  fi

  DUPLICATEPFILE=${ORACLE_HOME}/dbs/init${TARGET_DB}_duplicate.ora
  info "Create ${DUPLICATEPFILE} pfile"
  echo "db_name=${TARGET_DB}" > ${DUPLICATEPFILE}
  echo "${COMPATIBLE}" >> ${DUPLICATEPFILE}

  info "Place ${TARGET_DB} in nomount mode"
  if ! sqlplus -s / as sysdba << EOF
    whenever sqlerror exit failure
    startup force nomount pfile=${DUPLICATEPFILE}
EOF
  then
    error "Placing ${TARGET_DB} in nomount mode"
  fi
fi

info "Generating rman command file"
build_rman_command_file

if [[ "${NOOP_MODE}" != "TRUE" ]];
then
    info "Running rman cmd file $RMANDUPLICATECMDFILE"
    info "Please check progress ${RMANDUPLICATELOGFILE} ..."
rman log $RMANDUPLICATELOGFILE <<EOF > /dev/null
$CONNECT_TYPE
$CONNECT_TO_CATALOG
@$RMANDUPLICATECMDFILE
EOF
    info "Checking for errors"
    grep -i "ERROR MESSAGE STACK" $RMANDUPLICATELOGFILE>/dev/null 2>&1 && error "Rman Duplicate reported errors" || info "RMAN Duplicate Completed successfully"
    # Do not perform post actions when duplicating from legacy when the following options are specified
    if [[ ! "${LEGACY_OPTION}" =~ ^(restore|recover)$ ]]; then
      info "Perform post actions"
      post_actions
    fi
else
    info "Skipping duplicating database in noop mode"
    sqlplus -s / as sysdba << EOSQL
    startup force;
EOSQL
fi

[[ ! -z "$REPOSITORY_DISPATCH" ]] && github_repository_dispatch "oracle-rman-duplicate-success" "${JSON_INPUTS}"
info "Completed successfully"
# Exit with success status if no error found
trap "" ERR EXIT
exit 0
