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
  echo "  $THISSCRIPT -d <target db> -s <source db> -c <catalog db> -u <catalog schema> -t <restore datetime> [ -f <spfile parameters> ] [-l]"
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
  echo "  The SSM parameter path optionally specified with -s is used to identify the path for storing the phase, "
  echo "     status, and status messages for a dupicate held in a JSON string at this location."
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
#  EVENT_TYPE is a user-defined event to pass to the GitHub repository.   The backup worflow is triggered
#  for either oracle-db-duplicate-sucess or oracle-db-duplicate-failure events.   These are the only 2 which
#  should be used.
#  JSON_PAYLOAD is the JSON originally passed to the script using the -j switch.  This allows the
#  workflow to continue where it left off because this JSON contains the name of the environment, host
#  and period of the backup, along with any associated parameters.
EVENT_TYPE=$1
JSON_PAYLOAD=$2
GITHUB_TOKEN_VALUE=$(get_github_token | jq -r '.token')
# We set the Phase in the JSON payload corresponding to whether the backup has succeeded or failed.
# This is informational only - it is GitHub event type (oracle-db-backup-success/failure) which 
# determines what the workflow does next.
if [[ "$EVENT_TYPE" == "oracle-rman-duplicate-success" ]]; then
    JSON_PAYLOAD=$(echo $JSON_PAYLOAD | jq -r '.Phase = "Duplicate Succeeded"')
else
    JSON_PAYLOAD=$(echo $JSON_PAYLOAD | jq -r '.Phase = "Duplicate Failed"')
fi
JSON_DATA="{\"event_type\": \"${EVENT_TYPE}\",\"client_payload\":${JSON_PAYLOAD}}"
info "Posting repository dispatch event"
curl -X POST -H "Accept: application/vnd.github+json" -H "Authorization: token ${GITHUB_TOKEN_VALUE}"  --data-raw "${JSON_DATA}" "${REPOSITORY_DISPATCH}"
RC=$?
if [[ $RC -ne 0 ]]; then
      # We cannot use the error function for dispatch failures as it contains its own dispatch call   
      T=`date +"%D %T"`
      echo "ERROR : $THISSCRIPT : $T : Failed to dispatch ${EVENT_TYPE} event to ${REPOSITORY_DISPATCH}"
      # update_ssm_parameter  "Error" "Failed to dispatch ${EVENT_TYPE} event to ${REPOSITORY_DISPATCH}"
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
  # [[ ! -z "$SSM_PARAMETER" ]] && update_ssm_parameter "Error" "Error: $1"
  [[ ! -z "$REPOSITORY_DISPATCH" ]] && github_repository_dispatch "oracle-rman-duplicate-failure" "${JSON_INPUTS}"
  exit $ERROR_STATUS
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
while getopts "d:s:c:u:t:f:l:r:j:" opt
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
    *) usage ;;
  esac
done

if [[ ! -z "$REPOSITORY_DISPATCH" ]]; then
   REPOSITORY_DISPATCH="https://api.github.com/repos/${REPOSITORY_DISPATCH}/dispatches"
   info "GitHub Actions Repository Dispatch Events will be sent to : $REPOSITORY_DISPATCH"
fi

if [[ ! -z "$JSON_INPUTS" ]]; then
   # The JSON Inputs are used to record the parameters originally passed to GitHub
   # actions to start the backup job.   These are only used for actioning a repository
   # dispatch event to indicate the end of the backup job run.  They do NOT
   # override the command line options passed to the script.
   JSON_INPUTS=$(echo $JSON_INPUTS | base64 --decode )
fi

[[ ! -z "$REPOSITORY_DISPATCH" ]] && github_repository_dispatch "oracle-rman-duplicate-success" "${JSON_INPUTS}"

# Exit with success status if no error found
trap "" ERR EXIT
exit 0
