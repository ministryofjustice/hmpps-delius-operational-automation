#!/bin/bash

typeset -u RUN_MODE
export RUN_MODE=LIVE

typeset -u DEBUG_MODE
export DEBUG_MODE=N

export THISSCRIPT=`basename $0`
export THISHOST=`uname -n`
export THISPROC=$$
typeset -u TARGET_DB_SID
export TIMESTAMP=`date +"%Y%m%d%H%M"`
export STATSLOGFILE=/tmp/stats$$.log
export STATSOUTPUT=/tmp/stats$$.out
export V_DATABASE=v\$database

export SUCCESS_STATUS=0
export WARNING_STATUS=1
export ERROR_STATUS=9

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
# (2) Billing costs associated with the GitHub hosted runner actively waiting whilst the stats runs.
#
# We supply 2 parameters to this function:
#  EVENT_TYPE is a user-defined event to pass to the GitHub repository.   The stats worflow is triggered
#  for either oracle-db-stats-sucess or oracle-db-stats-failure events.   These are the only 2 which
#  should be used.
#  JSON_PAYLOAD is the JSON originally passed to the script using the -j switch.  This allows the
#  workflow to continue where it left off because this JSON contains the name of the environment, host
#  and period of the stats, along with any associated parameters.
EVENT_TYPE=$1
JSON_PAYLOAD=$2
GITHUB_TOKEN_VALUE=$(get_github_token | jq -r '.token')
# We set the Phase in the JSON payload corresponding to whether the stats has succeeded or failed.
# This is informational only - it is GitHub event type (oracle-db-stats-success/failure) which 
# determines what the workflow does next.
if [[ "$EVENT_TYPE" == "oracle-db-stats-success" ]]; then
    JSON_PAYLOAD=$(echo $JSON_PAYLOAD | jq -r '.Phase = "Stats Succeeded"')
else
    JSON_PAYLOAD=$(echo $JSON_PAYLOAD | jq -r '.Phase = "Stats Failed"')
fi
# GitHub Actions only allows us to have 10 elements in the payload so we remove those which are
# not necessary.  In this case we remove TargetHost since that is only relevant to the original
# stats; any retries will use RmanTarget instead.
#  JSON_PAYLOAD=$(echo $JSON_PAYLOAD | jq -r 'del(.TargetHost)')
info "Repository Dispatch Payload: $JSON_PAYLOAD"
JSON_DATA="{\"event_type\": \"${EVENT_TYPE}\",\"client_payload\":${JSON_PAYLOAD}}"
info "Posting repository dispatch event"
curl -X POST -H "Accept: application/vnd.github+json" -H "Authorization: token ${GITHUB_TOKEN_VALUE}"  --data-raw "${JSON_DATA}" ${REPOSITORY_DISPATCH}
RC=$?
if [[ $RC -ne 0 ]]; then
      # We cannot use the error function for dispatch failures as it contains its own dispatch call   
      T=`date +"%D %T"`
      echo "ERROR : $THISSCRIPT : $T : Failed to dispatch ${EVENT_TYPE} event to ${REPOSITORY_DISPATCH}" | tee -a ${STATSOUTPUT}
#      update_ssm_parameter  "Error" "Failed to dispatch ${EVENT_TYPE} event to ${REPOSITORY_DISPATCH}"hh
      exit 1
fi
}

# Parse command-line arguments
while getopts "u:p:r:j:" opt; do
  case $opt in
#    d) TARGET_DB_SID=$OPTARG ;;
    u) SCHEMAS=$OPTARG ;;
    p) PARALLELISM=$OPTARG ;;
#   s) SSM_PARAMETER=$OPTARG ;;
    r) REPOSITORY_DISPATCH=$OPTARG ;;
    j) JSON_INPUTS=$OPTARG ;;
    *) usage ;;
  esac
done

set_ora_env () {
  export ORAENV_ASK=NO
  export ORACLE_SID=$1
  . oraenv
  unset SQLPATH
  unset TWO_TASK
  unset LD_LIBRARY_PATH
  export NLS_DATE_FORMAT=YYMMDDHH24MI
}

info () {
  T=`date +"%D %T"`
  echo "INFO : $THISSCRIPT : $1" | tee -a ${STATSOUTPUT}
  if [ "$DEBUG_MODE" = "Y" ]
  then
    read CONTINUE?"Press any key to continue "
  fi
}

warning () {
  T=`date +"%D %T"`
  echo "WARNING : $THISSCRIPT : $1"
}

error () {
  T=`date +"%D %T"`
  echo "ERROR : $THISSCRIPT : $1" | tee -a ${STATSOUTPUT}
  #  [[ ! -z "$SSM_PARAMETER" ]] && update_ssm_parameter "Error" "Error: $1"
  [[ ! -z "$REPOSITORY_DISPATCH" ]] && github_repository_dispatch "oracle-db-stats-failure" "${JSON_INPUTS}"
  exit $ERROR_STATUS
}

# update_ssm_parameter () {
#   STATUS=$1
#   MESSAGE=$2
#   info "Updating SSM Parameter ${SSM_PARAMETER} Message to ${MESSAGE}"
#   SSM_VALUE=$(aws ssm get-parameter --name "${SSM_PARAMETER}" --query "Parameter.Value" --output text)
#   NEW_SSM_VALUE=$(echo ${SSM_VALUE} | jq -r --arg MESSAGE "$MESSAGE" '.Message=$MESSAGE')
#   if [[ "$STATUS" == "Success" ]]; then
#      NEW_SSM_VALUE=$(echo ${NEW_SSM_VALUE} | jq -r '.Phase = "Stats Succeeded"')
#   elif [[ "$STATUS" == "Running" ]]; then
#      NEW_SSM_VALUE=$(echo ${NEW_SSM_VALUE} | jq -r '.Phase = "Stats In Progress"') 
 #  else
#      NEW_SSM_VALUE=$(echo ${NEW_SSM_VALUE} | jq -r '.Phase = "Stats Failed"')
#   fi
# #   aws ssm put-parameter --name "${SSM_PARAMETER}" --type String --overwrite --value "${NEW_SSM_VALUE}" 1>&2
# }

validate () {
  ACTION=$1
  case "$ACTION" in
       user) info "Validating user"
             THISUSER=`id | cut -d\( -f2 | cut -d\) -f1`
             [ "$THISUSER" != "oracle" ] && error "Must be oracle to run this script"
             info "User ok"
             ;;
          *) error "Incorrect parameter passed to vaidate function"
             ;;
#     targetdb) info "Validating target database"
#              [ -z "$TARGET_DB_SID" -o "$TARGET_DB_SID" = "UNSPECIFIED" ] && usage
#              grep ^${TARGET_DB_SID}: /etc/oratab >/dev/null 2>&1
#              [ $? -ne 0 ] && error "Database $TARGET_DB_SID does not exist on this machine"
#              info "Target database ok"
#              info "Set environment for $TARGET_DB_SID"
#              set_ora_env $TARGET_DB_SID
#              ;;         
  esac
}

#get_db_status () {
 # ps -eo args | grep ^ora_smon_${TARGET_DB_SID} >/dev/null 2>&1
#  if [ $? -eq 0 ]
 # then
 #   X=`sqlplus -s "/ as sysdba" <<EOF
 #        whenever sqlerror exit 1
 #        set feedback off heading off verify off echo off
 #        select 'DB_STATUS="'||upper(open_mode)||'"' from $V_DATABASE ;
#         exit
# EOF
`
    [ $? -ne 0 ] && error "Cannot determine target status"
    eval $X
    info "Target status = $DB_STATUS"
  fi
}

validate user

info "Execute $THISUSER bash profile"
. $HOME/.bash_profile

# get_db_status

if [[ ! -z "$REPOSITORY_DISPATCH" ]]; then
   REPOSITORY_DISPATCH="https://api.github.com/repos/${REPOSITORY_DISPATCH}/dispatches"
   info "GitHub Actions Repository Dispatch Events will be sent to : $REPOSITORY_DISPATCH"
fi

if [[ ! -z "$JSON_INPUTS" ]]; then
   # The JSON Inputs are used to record the parameters originally passed to GitHub
   # actions to start the stats job.   These are only used for actioning a repository
   # dispatch event to indicate the end of the stats job run.  They do NOT
   # override the command line options passed to the script.
   JSON_INPUTS=$(echo $JSON_INPUTS | base64 --decode )
elif [[ ! -z "$REPOSITORY_DISPATCH" ]]; then
   error "JSON inputs must be supplied using the -j option if Repository Dispatch Events are requested."
fi

# if [[ ! -z "$SSM_PARAMETER" ]]; then
#   info "Runtime status updates will be written to: $SSM_PARAMETER"
#    update_ssm_parameter "Running" "Running: $0 $*"
fi

# Check if required variables are set
[ -z "$SCHEMAS" ] && usage
[ -z "$PARALLELISM" ] && PARALLELISM=1  # Default to 1 if not provided

# Run the SQL*Plus command
sqlplus -s "/ as sysdba" <<EOF
whenever sqlerror exit 1
set feedback off heading off verify off echo off
BEGIN
  DBMS_STATS.gather_schema_stats(
      ownname => '${SCHEMAS}'
      ,degree  => '${PARALLELISM}'
      ,no_invalidate => FALSE
  );
END;
/
exit
EOF
# Check for errors
info "Checking for errors"
grep -i "ERROR MESSAGE STACK" $STATSLOGFILE >/dev/null 2>&1
[ $? -eq 0 ] && error "Stats reported errors"
# [[ ! -z "$SSM_PARAMETER" ]] && update_ssm_parameter "Success" "Completed without errors"
[[ ! -z "$REPOSITORY_DISPATCH" ]] && github_repository_dispatch "oracle-db-stats-success" "${JSON_INPUTS}"
info "Completes successfully"

# Exit with success status if no error found
exit 0
