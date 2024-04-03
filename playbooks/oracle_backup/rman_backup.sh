#!/bin/bash

typeset -u RUN_MODE
export RUN_MODE=LIVE

typeset -u DEBUG_MODE
export DEBUG_MODE=N

export THISSCRIPT=`basename $0`
export THISHOST=`uname -n`
export THISPROC=$$
typeset -u CATALOG_DB
typeset -u TARGET_DB_SID
typeset -u BACKUP_TYPE
typeset -u CATALOGMODE
typeset -i LEVEL
typeset -u UNCOMPRESSED
typeset -u MINIMIZE_LOAD
typeset -u DEBUG_TRACE_FILE

export TIMESTAMP=`date +"%Y%m%d%H%M"`
export RMANREGISTERLOGFILE=/tmp/rmanregister${TARGET_DB_NAME}.log
export RMANLOGFILE=/tmp/rman$$.log
export RMANCMDFILE=/tmp/rman$$.cmd
export RMANTRCFILE=/tmp/rman$$.trc
export RMANOUTPUT=/tmp/rman$$.out

typeset -r MIN_LOG=0
typeset -r MAX_LOG=9999999999

export V_DATABASE=v\$database

export SUCCESS_STATUS=0
export WARNING_STATUS=1
export ERROR_STATUS=9

usage () {
  echo ""
  echo "Usage:"
  echo ""
  echo "  $THISSCRIPT -d <target db sid> -t <backup type> [ -b <bucket> ] [ -f <backup dir> ] [ -i <incremental level> ] [ -m <minimize load>] [ -u <uncompressed> ] "
  echo "                                              [ -n <catalog> ] [ -c <catalog db> ] [ -e <enable trace> ] "
  echo "                                              [ -a min archivelog sequence,max archivelog sequence ] "
  echo "                                              [ -l <comma separated list of datafiles to backup> ] "
  echo "                                              [ -g <target db global name> ]"
  echo "                                              [ -s <SSM Parameter Path where Runtime details are written>]"
  echo "                                              [ -r <GitHub repository for sending repository dispatch events back to the calling workflow>] "
  echo "                                              [ -j <JSON formatted string of inputs to the Github backup workflow>] "
  echo ""
  echo "where"
  echo ""
  echo "  target db   = SID of database to be backed up"
  echo "  target db global name = Name of database to be backed up (defaults to SID if not specified)"
  echo "  backup type = HOT or COLD"
  echo "  bucket = Y or N if backing up to S3 bucket"
  echo "  backup dir = filesystem backup directory"
  echo "  incremental level = 0 or 1."
  echo "  minimize load = backup target runtime in HH:MI format"
  echo "  uncompressed  = Y/N flag indicating whether or not a non-compressed"
  echo "                backupset should be created.  Default is N."
  echo "  catalog     = Y/N flag indicating whether or not the backup uses"
  echo "                rman nocatalog mode or not. Default is N."
  echo "  catalog db  = database where the rman repository resides"
  echo "  trace       = Y/N flag indicating whether to enable RMAN trace.  Default is N."
  echo "  archivelogs = range of archivelogs to backup in format of minimum sequence,maximum sequence (e.g. 100,110 ).  Do not put spaces around the comma."
  echo "  "
  echo "  If -a or -l is NOT specified then a full backup of the database and all archivelogs not already backed up is performed."
  echo "     -a and -l are mutually exclusive.  If you wish to backup a range of archivelogs and some datafiles then call the script twice "
  echo "     with the respective parameters."
  echo "  "
  echo "  If -r is specified then a repository must be specified for sending GitHub actions repository dispatch events."
  echo "      This would typically be ministryofjustice/hmpps-delius-operational-automation and is used for triggering"
  echo "      any follow-on GitHub actions necessary upon succesful or unsuccessful completion."
  echo "  "
  echo "  If -j is specified then it should be followed by a valid JSON string representing all of the inputs to the GitHub"
  echo "       backup workflow.  This is used to supply the original input parameters back to the GitHub workflow in the case"
  echo "       that we wish to continue the workflow after this script has finished running. This parameter is mandatory"
  echo "       if -r is used to specify the use of repository dispatch events."
  echo ""
  echo "  The SSM parameter path optionally specified with -s is used to identify the path for storing the phase, "
  echo "     status, and status messages for a backup held in a JSON string at this location."

  exit $ERROR_STATUS
}


function generate_jwt()
{
# Get a JSON Web Token to authenicate against the HMPPS Bot.
# The HMPPS bot can provide exchange this for a GitHub Token for action GitHub workflows.

BOT_APP_ID=$(aws ssm get-parameter --name "/github/hmpps_bot_app_id" --query "Parameter.Value" --with-decryption --output text)
BOT_PRIVATE_KEY=$(aws ssm get-parameter --name "/github/hmpps_bot_priv_key" --query "Parameter.Value" --with-decryption --output text)

# Define expiry time for JWT
NOW=$(date +%s)
INITIAL=$((${NOW} - 60)) # Issues 60 seconds in the past
EXPIRY=$((${NOW} + 600)) # Expires 10 minutes in the future

b64enc() { openssl base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n'; }

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
# Payload encode
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
EVENT_TYPE=$1
JSON_PAYLOAD=$2
GITHUB_TOKEN_VALUE=$(get_github_token | jq -r '.token')
echo <<EOCURL
curl -X POST -H "Accept: application/vnd.github+json" -H "Authorization: token ${GITHUB_TOKEN_VALUE}"  --data "{\"event_type\": \"${EVENT_TYPE}\",\"client_payload\":${JSON_PAYLOAD}}" ${REPOSITORY_DISPATCH}
EOCURL
curl -X POST -H "Accept: application/vnd.github+json" -H "Authorization: token ${GITHUB_TOKEN_VALUE}"  --data "{\"event_type\": \"${EVENT_TYPE}\",\"client_payload\":${JSON_PAYLOAD}}" ${REPOSITORY_DISPATCH}
RC=$?
if [[ $RC -ne 0 ]]; then
      # We cannot use the error function for dispatch failures as it contains its own dispatch call   
      T=`date +"%D %T"`
      echo "ERROR : $THISSCRIPT : $T : Failed to dispatch ${EVENT_TYPE} event to ${REPOSITORY_DISPATCH}" | tee -a ${RMANOUTPUT}
      update_ssm_parameter "Error" "Failed to dispatch ${EVENT_TYPE} event to ${REPOSITORY_DISPATCH}"
      exit 1
fi
}

info () {
  T=`date +"%D %T"`
  echo "INFO : $THISSCRIPT : $T : $1" | tee -a ${RMANOUTPUT}
  if [ "$DEBUG_MODE" = "Y" ]
  then
    read CONTINUE?"Press any key to continue "
  fi
}

warning () {
  T=`date +"%D %T"`
  echo "WARNING : $THISSCRIPT : $T : $1"
}

update_ssm_parameter () {
  # We do not change the backup phase within this script - it is always BACKUP
  # We can only change the status of the run
  STATUS=$1
  MESSAGE=$2
  info "Updating SSM Parameter ${SSM_PARAMETER} Status to ${STATUS}"
  SSM_VALUE=$(aws ssm get-parameter --name "${SSM_PARAMETER}" --query "Parameter.Value" --output text)
  NEW_SSM_VALUE=$(echo ${SSM_VALUE} | jq --arg STATUS "$STATUS" '.Status=$STATUS' | jq -r --arg MESSAGE "$MESSAGE" '.Message=$MESSAGE')
  aws ssm put-parameter --name "${SSM_PARAMETER}" --type String --overwrite --value "${NEW_SSM_VALUE}" 1>&2
}

error () {
  T=`date +"%D %T"`
  echo "ERROR : $THISSCRIPT : $T : $1" | tee -a ${RMANOUTPUT}
  [[ ! -z "$SSM_PARAMETER" ]] && update_ssm_parameter "Error" "$1"
  [[ ! -z "$REPOSITORY_DISPATCH" ]] && github_repository_dispatch "oracle-db-backup-failure" "${JSON_INPUTS}"
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

get_rman_password () {
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ASSUME_ROLE_NAME}"
  SESSION="catalog-ansible"
  CREDS=$(aws sts assume-role --role-arn "${ROLE_ARN}" --role-session-name "${SESSION}"  --output text --query "Credentials.[AccessKeyId,SecretAccessKey,SessionToken]")
  # Avoid exporting the AWS_* variables as we only need to change the role for fetching the RMAN password.
  # The existing role should continue to be used for other functionality.  Therefore only use AWS_* variables within the subshell.
  export RMAN_ACCESS_KEY_ID=$(echo "${CREDS}" | tail -1 | cut -f1)
  export RMAN_SECRET_ACCESS_KEY=$(echo "${CREDS}" | tail -1 | cut -f2)
  export RMAN_SESSION_TOKEN=$(echo "${CREDS}" | tail -1 | cut -f3)
  SECRET_ARN="arn:aws:secretsmanager:eu-west-2:${SECRET_ACCOUNT_ID}:secret:${SECRET}"
  RMANPASS=$(AWS_ACCESS_KEY_ID=$RMAN_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY=$RMAN_SECRET_ACCESS_KEY AWS_SESSION_TOKEN=$RMAN_SESSION_TOKEN aws secretsmanager get-secret-value --secret-id "${SECRET_ARN}" --query SecretString --output text | jq -r .rcvcatowner)
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
             [ -z "$TARGET_DB_SID" -o "$TARGET_DB_SID" = "UNSPECIFIED" ] && usage
             grep ^${TARGET_DB_SID}: /etc/oratab >/dev/null 2>&1
             [ $? -ne 0 ] && error "Database $TARGET_DB_SID does not exist on this machine"
             info "Target database ok"
             info "Set environment for $TARGET_DB_SID"
             set_ora_env $TARGET_DB_SID
             ;;
 backuptype) info "Validating backup type"
             case "$BACKUP_TYPE" in
               HOT|COLD ) if [ "$BACKUP_TYPE" = "HOT" ]
                          then
                            case $LEVEL in
                              0|1) ;;
                                *) error "Please secify correct incremental level"
                            esac
                          fi ;;
                      * ) usage ;;
             esac
             info "Backup type ok"
             ;;
     bucket) info "Validating s3 bucket"
             if [ "$BUCKET" = "Y" ]
             then
               info "Backup S3 Bucket = $BUCKET"
             else
               info "Not backing up to S3 bucket"
             fi
             ;;
  backupdir) info "Validating backup directory"
             if [ "$BACKUPDIR" != "UNSPECIFIED" ]
             then
               [ -z $BACKUPDIR ] && error "Please specify backup directory"
               [ ! -d $BACKUPDIR/$TARGET_DB_NAME ] && error "$BACKUPDIR/$TARGET_DB_NAME does not exist"
               [ "$BUCKET" = "Y" ] && error "Cannot specify both S3 bucket and $BACKUPDIR"
             fi
             info "Backup directory ok"
             ;;
    uncompressed) info "Validating uncompressed flag"
                  case "$UNCOMPRESSED" in
                     Y|N ) info "Uncompressed flag ok"
                           ;;
                       * ) error "Incorrect uncompressed flag must be Y or N"
                  esac
                  ;;
    duration) info "Validating backup duration for minimizing load"
              if [[ "$MINIMIZE_LOAD" == "UNSPECIFIED" ]];
              then
                 info "No load duration target set"
                 return
              fi
              HOURS=$( echo $MINIMIZE_LOAD | cut -d: -f1 )
              MINS=$( echo $MINIMIZE_LOAD | cut -d: -f2 )
              if [[ $MINS =~ ^[0-9][0-9]$ && $MINS -ge 0 && $MINS -lt 60 ]]; 
              then
                 if [[ $HOURS =~ ^[0-9]+$ && $HOURS -ge 0 && $HOURS -lt 100 ]]; 
                 then   
                    info "Load duration ok at $HOURS hours and $MINS minutes"
                 else
                    error "Incorrect number of hours in load duration"
                 fi
              else
                 error "Incorrect number of minutes in load duration"
              fi
              ;;
    archivelogs) info "Validating the archivelog range specified"
                 if [[ "$DATAFILES" != "UNSPECIFIED" ]]
                 then
                    error "Archivelog and Datafiles backups are mutually exclusive"
                 fi
                 MIN_ARCHIVELOG=$(echo $ARCHIVELOGS | cut -d, -f1)
                 MAX_ARCHIVELOG=$(echo $ARCHIVELOGS | cut -d, -f2)
                 if [[ $MIN_ARCHIVELOG =~ ^[0-9]+$ && $MAX_ARCHIVELOG =~ ^[0-9]+$ ]];
                 then 
                    if [[ $MIN_ARCHIVELOG -le $MAX_ARCHIVELOG ]];
                    then
                       info "Backing archivelog sequence between $MIN_ARCHIVELOG and $MAX_ARCHIVELOG"
                    else
                       error "Maximum archivelog sequence must be equal or higher than Minimum archivelog sequence"
                    fi
                 else
                    error "Non-numeric archivelog sequence specified"
                 fi
                 ;;
    catalog) info "Validating catalog flag"
             case "$CATALOGMODE" in
               Y|N ) if [ "$CATALOGMODE" = "Y" ]
                     then
                       if [ -z $CATALOG_DB ]
                       then
                         error "Catalog mode is $CATALOGMODE, specify catalog db"
                       else
                         get_rman_password
                         [ -z ${RMANPASS} ] && error "Password for RMAN catalog user rcvcatowner does not exist"
                         CATALOG_CONNECT=rcvcatowner/${RMANPASS}@$CATALOG_DB
                       fi
                     fi
                     ;;
                  *) error "Incorrect catalog flag must be Y or N"
             esac
             info "Catalog flag ok"
             ;;
          *) error "Incorrect parameter passed to vaidate function"
             ;;
  esac
}


get_db_status () {
  ps -eo args | grep ^ora_smon_${TARGET_DB_SID} >/dev/null 2>&1
  if [ $? -eq 0 ]
  then
    X=`sqlplus -s "/ as sysdba" <<EOF
         whenever sqlerror exit 1
         set feedback off heading off verify off echo off
         select 'DB_STATUS="'||upper(open_mode)||'"' from $V_DATABASE ;
         exit
EOF
`
    [ $? -ne 0 ] && error "Cannot determine target status"
    eval $X
    info "Target status = $DB_STATUS"
  fi
}

get_db_role () {
  DATABASE_ROLE=$(srvctl config database -d ${ORACLE_SID} | awk -F: '/Database role/{print $2}' | xargs)
  info "Database role = $DATABASE_ROLE"
}

cold_check () {
  info "Checking the database is up and in correct mode"
  ps -eo args | grep ^ora_smon_${TARGET_DB_SID} >/dev/null 2>&1
  if [ $? -eq 0 ]
  then
    [ "$DB_STATUS" != "READ WRITE" ] && error "Target database must be in READ WRITE mode"
  fi
}

hot_check () {
  info "Checking target database is in archivelog mode"
  ps -ef | grep ora_smon_${TARGET_DB_SID} >/dev/null 2>&1
  [ $? -ne 0 ] && error "Target database is not active"
  X=`sqlplus -s "/ as sysdba" <<EOF
        set feedback off heading off verify off echo off
        select 'LOG_MODE='||log_mode from $V_DATABASE;
        exit
EOF
`
  eval $X
  info "Archivelog mode = $LOG_MODE"
  [ "$LOG_MODE" != "ARCHIVELOG" ] && error "Target database not in archivelog mode"
  info "Target database in archivelog mode"
}

catalog_check () {
  info "Checking Database ID"
  X=`sqlplus -s "/ as sysdba" <<EOF
       set feedback off heading off echo off verify off
       select 'DB_ID='||DBID from $V_DATABASE;
       exit
EOF
`
  eval $X

  info "Database ID = $DB_ID"

  info "Checking if target database is registered"
   X=`sqlplus -s $CATALOG_CONNECT <<EOF
        set feedback off heading off echo off verify off
        select 'ISREGD='||decode(count(*),0,'NO','YES')
          from rc_database
         where name = '$TARGET_DB_NAME'
         and dbid = '$DB_ID';
        exit
EOF
`
  eval $X

  if [ "$ISREGD" = "NO" ]
  then
    info "Registering target database"
    rman log $RMANREGISTERLOGFILE <<ERMANREG
connect catalog $CATALOG_CONNECT ;
connect target /
register database ;
exit
ERMANREG
    grep -i "ERROR MESSAGE STACK" $RMANREGISTERLOGFILE >/dev/null 2>&1
    [ $? -eq 0 ] && error "Rman reported errors"
  else
    info "Target database already registered"
  fi
}

create_tag_format () {
  [ "$BACKUP_TYPE" = "HOT" ] && LABEL="LEVEL${LEVEL}" || LABEL="COLD"
  label=`echo "${LABEL}" | tr '[:upper:]' '[:lower:]'`
  if [ "$BUCKET" = "Y" ]
  then
    DIR=""
  else
    DIR="${BACKUPDIR}/${TARGET_DB_NAME}/"
  fi
  DB_TAG_FORMAT="tag=DB_${LABEL}_${TIMESTAMP} format '${DIR}${label}_db_%T_%d_%U'"
  AL_TAG_FORMAT="tag=ARCH_${LABEL}_${TIMESTAMP} format '${DIR}${label}_al_%T_%d_%U'"
  CF_TAG_FORMAT="tag=CONTROL_${LABEL}_${TIMESTAMP} format '${DIR}${label}_cf_%T_%d_%U'"
  DF_TAG_FORMAT="tag=DATAFILE_${LABEL}_${TIMESTAMP} format '${DIR}${label}_df_%T_%d_%U'"

  if [ "$BACKUPDIR" = "UNSPECIFIED" -a  "$BUCKET" = "N" ]
  then
    DB_TAG_FORMAT="tag=db_${label}_${TIMESTAMP}"
    AL_TAG_FORMAT="tag=arch_${label}_${TIMESTAMP}"
    CF_TAG_FORMAT="tag=control_${label}_${TIMESTAMP}"
    DF_TAG_FORMAT="tag=datafile_${label}_${TIMESTAMP}"
  fi
}


check_control_file_record_keep_time () {

  # Check that the Control File Record Keep time is long enough for the
  # required RMAN Recovery Window (if specified in Days) when NOCATALOG
  V_PARAMETER=v\$parameter
  X=`sqlplus -s "/ as sysdba" <<EOF
     whenever sqlerror exit 1
     set feedback off heading off verify off echo off
     select 'CONTROL_FILE_RECORD_KEEP_TIME="'||value||'"' from $V_PARAMETER
     where name = 'control_file_record_keep_time';
     exit
EOF
`
  [ $? -ne 0 ] && error "Cannot determine control_file_record_keep_time"
  eval $X
  info "control file record keep time = $CONTROL_FILE_RECORD_KEEP_TIME"  
   
  RETENTION_POLICY=`rman target / <<EOF
     show retention policy;
     exit
EOF
`

  MATCH_REGEX="CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF [0-9]+ DAYS;"
  if [[ $RETENTION_POLICY =~ $MATCH_REGEX ]];
  then 
      RECOVERY_WINDOW=$(echo $RETENTION_POLICY | grep -P "(?<=WINDOW OF )\d+(?= DAYS)" -o)
      if [[ $RECOVERY_WINDOW -gt $CONTROL_FILE_RECORD_KEEP_TIME ]];
      then
          sqlplus -s "/ as sysdba" <<EOF
          whenever sqlerror exit 1
          alter system set control_file_record_keep_time=${RECOVERY_WINDOW};
          exit       
EOF
      [ $? -ne 0 ] && error "Cannot set control file record keep time to accommodate recovery window of ${RECOVERY_WINDOW} days"
      eval $X
      info "Increased the control file record keep time to ${RECOVERY_WINDOW} due to size of RMAN Recovery Window (and no catalog in use)"  
      fi
      # Nothing to do if control_file_record_keep_time is already large enough
  fi
  # Nothing to do if Retention Policy is not defined in terms of a Recovery Window
}

build_rman_command_file () {

  # Initialize empty command file
  >$RMANCMDFILE

  V_PARAMETER=v\$parameter
  X=`sqlplus -s "/ as sysdba" <<EOF
     whenever sqlerror exit 1
     set feedback off heading off verify off echo off
     select 'CPU_COUNT="'||value||'"' from $V_PARAMETER
     where name = 'cpu_count';
     exit
EOF
`

  [ $? -ne 0 ] && error "Cannot determine cpu count"
  eval $X
  info "cpu count = $CPU_COUNT"

  if [ "$CATALOGMODE" = "Y" ]
  then
    CONNECT_TO_CATALOG=$(echo "connect catalog $CATALOG_CONNECT;")								
  else
     check_control_file_record_keep_time
  fi

  if [ "$TRACE_FILE" = "Y" ]
  then
     echo "set echo on;"              >>$RMANCMDFILE
     echo "debug on;"              	  >>$RMANCMDFILE
  fi

  echo "run {"												>>$RMANCMDFILE
  if [ "$BUCKET" = "Y" ]
  then
    TYPE="sbt\n  parms='SBT_LIBRARY=${ORACLE_HOME}/lib/libosbws.so,\n  ENV=(OSB_WS_PFILE=${ORACLE_HOME}/dbs/osbws.ora)';"
  else
    TYPE="disk;"
  fi
  for (( i=1; i<=${CPU_COUNT}; i++ ))
  do
    echo -e "  allocate channel c${i} device type $TYPE" 						>> $RMANCMDFILE
  done
  if [[ "$DATABASE_ROLE" = "PHYSICAL_STANDBY" ]]
  then
    # If we are running the backup on a standby database it is possible that some archivelogs may have already
    # been deleted by the ARCHIVELOG DELETION POLICY of APPLIED ON STANDBY.  Therefore we need to run a 
    # crosscheck and delete first, otherwise any deleted archivelogs could case the script to error.
    echo "  crosscheck archivelog all;"                                                                   >>$RMANCMDFILE
    echo "  delete noprompt expired archivelog all;"                                                      >>$RMANCMDFILE
  fi
  if [ "$BACKUP_TYPE" = "COLD" ]
  then
    echo "  shutdown immediate;"                                                                         >> $RMANCMDFILE
    echo "  startup mount;"                                                                              >> $RMANCMDFILE
    if [[ "$UNCOMPRESSED" = "N" ]]
    then
        echo "  backup as compressed backupset"                                                          >> $RMANCMDFILE
    else
        echo "  backup as backupset;"                                                                    >> $RMANCMDFILE
    fi
    if [[ "$MINIMIZE_LOAD" != "UNSPECIFIED" ]]
    then
        echo "  duration $MINIMIZE_LOAD minimize load "                                                  >> $RMANCMDFILE
    fi
    echo "  database $DB_TAG_FORMAT;"                                                                    >> $RMANCMDFILE
    echo "  backup current controlfile $CF_TAG_FORMAT;"                                                  >> $RMANCMDFILE
    echo "  alter database open;"                                                                        >> $RMANCMDFILE
  elif [ "$BACKUP_TYPE" = "HOT" ]
  then
    if [[ "$ARCHIVELOGS" = "UNSPECIFIED" && $DATAFILES = "UNSPECIFIED" ]]    
    then
        if [ "$DB_STATUS" = "READ WRITE" ]
        then echo "  alter system archive log current; "                                                  >>$RMANCMDFILE
        fi
        echo "  backup archivelog all not backed up 1 times  $AL_TAG_FORMAT;"                   		      >>$RMANCMDFILE
    fi
    if [[ "$UNCOMPRESSED" = "N" ]]
    then
        echo "  backup as compressed backupset"                                                           >>$RMANCMDFILE
    else
        echo "  backup as backupset"                                                                      >>$RMANCMDFILE
    fi
    echo "  incremental level $LEVEL cumulative "                                                         >>$RMANCMDFILE
    if [[ "$MINIMIZE_LOAD" != "UNSPECIFIED" ]]
    then
        echo "  duration $MINIMIZE_LOAD minimize load "                                                  >> $RMANCMDFILE
    fi
    if [[ "$ARCHIVELOGS" = "UNSPECIFIED" && $DATAFILES = "UNSPECIFIED" ]]    
    then
        echo "  database $DB_TAG_FORMAT;"                                                                     >>$RMANCMDFILE
        if [ "$DB_STATUS" = "READ WRITE" ]
        then echo "  alter system archive log current; "                                                      >>$RMANCMDFILE
        fi
        echo "  backup archivelog all not backed up 1 times  $AL_TAG_FORMAT;"                   		          >>$RMANCMDFILE
        echo "  backup current controlfile $CF_TAG_FORMAT;"                                                   >>$RMANCMDFILE
        if [ "$DB_STATUS" = "READ WRITE" ]
        then echo "  alter system archive log current; "                                                      >>$RMANCMDFILE
        fi
        echo "  backup archivelog all not backed up 1 times  $AL_TAG_FORMAT;"                   		          >>$RMANCMDFILE
        # From 18c Onwards we need to explicitly allocate a disk channel for operations on disk backupsets (this is backwards compatible)
        # Allocate this __after__ the backup is complete as we do not want any of the above backup commands going to disk
        echo "  allocate channel d1 device type disk;"                                                        >>$RMANCMDFILE
        echo "  crosscheck archivelog all;"                                                                   >>$RMANCMDFILE
        echo "  crosscheck backup; "                                                                          >>$RMANCMDFILE
        echo "  delete expired backup;"                                                                       >>$RMANCMDFILE
        echo "  report obsolete;"                                                                             >>$RMANCMDFILE
        echo "  delete obsolete;"                                                                             >>$RMANCMDFILE
    fi
    if [[ "$ARCHIVELOGS" != "UNSPECIFIED" ]]
    then
        # We do not want Backup Optimization to prevent us backing up the archivelogs again if we specifically want
        # to do that, so we add "not backed up 1000 times" to allow us to override skipping of backed up archivelogs
        echo " archivelog sequence between $MIN_ARCHIVELOG and $MAX_ARCHIVELOG not backed up 1000 times   $AL_TAG_FORMAT;"            >>$RMANCMDFILE
    fi
    if [[ "$DATAFILES" != "UNSPECIFIED" ]]
    then 
        echo " datafile $DATAFILES   $DF_TAG_FORMAT;"                                                         >>$RMANCMDFILE
        echo " backup archivelog all not backed up 1 times  $AL_TAG_FORMAT;"                    		          >>$RMANCMDFILE
    fi
  fi
  for (( i=1; i<=${CPU_COUNT}; i++ ))
  do
    echo "  release channel c${i};"                                                   			  >> $RMANCMDFILE
  done
  # We only need to release the disk channel if allocated for the database backup
  # (Archive log and Data file backups will not have this channel as they do not perform expired and obsolete cleanup)
  if [[ "$ARCHIVELOGS" = "UNSPECIFIED" && $DATAFILES = "UNSPECIFIED" ]]   
  then
     echo "  release channel d1;"        >> $RMANCMDFILE
  fi
  echo "}"                            >> $RMANCMDFILE       
  
  if [ "$TRACE_FILE" = "Y" ]
  then
     echo "debug off;"                >>$RMANCMDFILE
  fi
                                                                                               >>$RMANCMDFILE
  echo "exit"												  >>$RMANCMDFILE
}

enable_bct () {
  V_BLOCK_CHANGE_TRACKING=v\$block_change_tracking
  X=`sqlplus -s "/ as sysdba" <<EOF
     whenever sqlerror exit 1
     set feedback off heading off verify off echo off
     select 'STATUS="'||status||'"' from $V_BLOCK_CHANGE_TRACKING;
     exit
EOF
`
  [ $? -ne 0 ] && error "Cannot determine block change tracking status"
  eval $X
  info "Block Change Tracking = $STATUS"

  # For Standby Databases, BCT is only allowed where ADG is in use
  START_OPTIONS=$(srvctl config database -d ${ORACLE_SID} | grep "Start options:" | awk -F: '{print $2}' | tr -d ' ' )

  if [[ "$STATUS" == "DISABLED" ]]
  then
     if [[ "${START_OPTIONS}" == "open" || "${START_OPTIONS}" == "readonly" ]]
     then 
        sqlplus -s / as sysdba <<EOF
        whenever sqlerror exit 1
        set feedback off heading off verify off echo off
        alter database enable block change tracking;
        exit
EOF
     else
        info "Block Change Tracking is not available for non-ADG standby"
     fi
  else
     if [[ "${START_OPTIONS}" != "open" && "${START_OPTIONS}" != "readonly" ]]
     then
        sqlplus -s / as sysdba <<EOF
        whenever sqlerror exit 1
        set feedback off heading off verify off echo off
        alter database disable block change tracking;
        exit
EOF
     else
        info "Block Change Tracking is already enabled"
     fi
  fi
  [ $? -ne 0 ] && error "Unable to enable block change tracking"
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
info "Starts"
unset ORACLE_SID
info "Retrieving arguments"
[ -z "$1" ] && usage

TARGET_DB_SID=UNSPECIFIED
BACKUP_TYPE=UNSPECIFIED
BUCKET=N
CATALOGMODE=N
BACKUPDIR=UNSPECIFIED
UNCOMPRESSED=N
MINIMIZE_LOAD=UNSPECIFIED
TRACE_FILE=N
ARCHIVELOGS=UNSPECIFIED
DATAFILES=UNSPECIFIED
while getopts "d:t:b:f:i:n:m:u:c:e:a:l:g:p:s:r:j:" opt
do
  case $opt in
    d) TARGET_DB_SID=$OPTARG ;;
    t) BACKUP_TYPE=$OPTARG ;;
    b) BUCKET=$OPTARG ;;
    f) BACKUPDIR=$OPTARG ;;
    i) LEVEL=$OPTARG ;;
    n) CATALOGMODE=$OPTARG ;;
    m) MINIMIZE_LOAD=$OPTARG ;;
    u) UNCOMPRESSED=$OPTARG ;;
    c) CATALOG_DB=$OPTARG ;;
    e) TRACE_FILE=$OPTARG ;;
    a) ARCHIVELOGS=$OPTARG ;;
    l) DATAFILES=$OPTARG ;;
    g) TARGET_DB_NAME=$OPTARG ;;
    s) SSM_PARAMETER=$OPTARG ;;
    r) REPOSITORY_DISPATCH=$OPTARG ;;
    j) JSON_INPUTS=$OPTARG ;;
    *) usage ;;
  esac
done
[ -z $TARGET_DB_NAME ] && TARGET_DB_NAME=$TARGET_DB_SID
info "Target SID          = $TARGET_DB_SID"
info "Target Name         = $TARGET_DB_NAME"
info "Backup type         = $BACKUP_TYPE"
info "S3 Bucket           = $BUCKET"
info "Catalog mode        = $CATALOGMODE"
info "Backup dir          = $BACKUPDIR/$TARGET_DB_NAME"
info "Uncompressed        = $UNCOMPRESSED"
info "Load Duration       = $MINIMIZE_LOAD"
info "Trace File          = $TRACE_FILE"
info "Archivelog Range    = $ARCHIVELOGS"
info "Specific Datafiles  = $DATAFILES"

validate user
info "Execute $THISUSER bash profile"
. $HOME/.bash_profile
validate targetdb
validate backuptype
#validate bucket
validate backupdir
validate catalog
validate uncompressed
validate duration
if [ "$ARCHIVELOGS" != "UNSPECIFIED" ]
then  
   validate archivelogs
fi
get_db_status
get_db_role
if [ "$BACKUP_TYPE" = "COLD" ]
then
   cold_check
elif [ "$BACKUP_TYPE" = "HOT" ]
then
   hot_check
fi

if [  "$CATALOGMODE" = "Y" ]
then
  catalog_check
else
  info "Not checking if DB is registered as running in NOCATALOG mode"
fi

info "Check if block change tracking is enable"
enable_bct

if [  "$TRACE_FILE" = "Y" ]
then
   info "Enabing RMAN Debug Trace File"
   ENABLE_TRACE="trace $RMANTRCFILE"
fi

if [[ ! -z "$SSM_PARAMETER" ]]; then
   info "Runtime status updates will be written to: $SSM_PARAMETER"
   update_ssm_parameter "Running" "Running $0 $*"
fi

if [[ ! -z "$REPOSITORY_DISPATCH" ]]; then
   REPOSITORY_DISPATCH="https://api.github.com/repos/${REPOSITORY_DISPATCH}/dispatches"
   info "GitHub Actions Repository Dispatch Events will be sent to : $REPOSITORY_DISPATCH"
fi

if [[ ! -z "$JSON_INPUTS" ]]; then
   # The JSON Inputs are used to record the parameters originally passed to GitHub
   # actions to start the backup job.   These are only used for actioning a repository
   # dispatch event to indicate the end of the backup job run.  They do NOT
   # override the command line options passed to the script.
   JSON_INPUTS=$(echo $JSON_INPUTS | base64 --decode)
   info "Original JSON Inputs to GitHub Action: $JSON_INPUTS"
elif [[ ! -z "$REPOSITORY_DISPATCH" ]]; then
   error "JSON inputs must be supplied using the -j option if Repository Dispatch Events are requested."
fi

touch $RMANCMDFILE
info "Create rman tags and format"
create_tag_format
info "Generating rman command file"
build_rman_command_file
info "Running rman cmd file $RMANCMDFILE"
info "Please check progress ${RMANLOGFILE} ..."
rman log $RMANLOGFILE $ENABLE_TRACE <<ERMAN > /dev/null
connect target /
$CONNECT_TO_CATALOG
@$RMANCMDFILE
ERMAN
info "Checking for errors"
grep -i "ERROR MESSAGE STACK" $RMANLOGFILE >/dev/null 2>&1
[ $? -eq 0 ] && error "Rman reported errors"
[[ ! -z "$SSM_PARAMETER" ]] && update_ssm_parameter "Success" "Completed without errors"
[[ ! -z "$REPOSITORY_DISPATCH" ]] && github_repository_dispatch "oracle-db-backup-success" "${JSON_INPUTS}"
info "Completes successfully"

# Exit with success status if no error found
exit 0
