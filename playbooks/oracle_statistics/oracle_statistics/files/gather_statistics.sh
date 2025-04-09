#!/bin/bash

export THISSCRIPT=`basename $0`
export THISDIRECTORY=`dirname $0`
STATISTICSOUTPUT=${THISDIRECTORY}/gather_statistics$$.out

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
#  for either oracle-db-statistics-sucess or oracle-db-statistics-failure events.   These are the only 2 which
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
if [[ "$EVENT_TYPE" == "oracle-db-statistics-success" ]]; then
    JSON_PAYLOAD=$(echo $JSON_PAYLOAD | jq -r '.Phase = "Statistics Succeeded"')
else
    JSON_PAYLOAD=$(echo $JSON_PAYLOAD | jq -r '.Phase = "Statistics Failed"')
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
  echo "ERROR : $THISSCRIPT : $T : Failed to dispatch ${EVENT_TYPE} event to ${REPOSITORY_DISPATCH}" | tee -a ${STATISTICSOUTPUT}
  exit 1
fi
}

info () {
  T=`date +"%D %T"`
  echo "INFO : $THISSCRIPT : $T : $1" | tee -a ${STATISTICSOUTPUT}
}

error () {
  T=`date +"%D %T"`
  echo "ERROR : $THISSCRIPT : $T : $1" | tee -a ${STATISTICSOUTPUT}
  [[ ! -z "$REPOSITORY_DISPATCH" ]] && github_repository_dispatch "oracle-db-statistics-failure" "${JSON_INPUTS}"
  exit 9
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
while getopts "s:p:r:j:t:" opt 
do
  case $opt in
    s) SCHEMAS=$OPTARG ;;
    p) PARALLELISM=$OPTARG ;;
    r) REPOSITORY_DISPATCH=$OPTARG ;;
    j) JSON_INPUTS=$OPTARG ;;
    t) TABLE_INPUTS=$OPTARG ;;
    *) echo "Incorrect parameters. Please check" 
       exit 1 ;;
  esac
done

info "Execute users bash profile"
. $HOME/.bash_profile

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
fi

info "Gather statistics for schemas ${SCHEMAS}" 
sqlplus -s "/ as sysdba" <<EOSQL
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
EOSQL

[[ $? -ne 0 ]] && error "In gathering statistics"

info "Unlocking statistics"

TABLE_INPUTS=$(echo $TABLE_INPUTS | base64 --decode )
for TABLE_INPUT in $(echo $TABLE_INPUTS | jq -c '.[]')
do
  SCHEMA=$(echo $TABLE_INPUT | jq -r '.schema_name')
  TABLE_LIST=$(echo $TABLE_INPUT | jq -c '.table_names[] | keys_unsorted | flatten[]' | sed "s/\"/'/g")
  TABLE_LIST=$(echo $TABLE_LIST | sed 's/ /,/g')
  info "Do not unlock ${TABLE_LIST}"
  SQLRESULT=$(sqlplus -s / as sysdba<<EOSQL
  connect / as sysdba

  WHENEVER SQLERROR EXIT FAILURE
  SET SERVEROUT ON

  DECLARE
    l_unlock_counter INTEGER := 0;
  BEGIN
  FOR t IN (SELECT table_name
            FROM   dba_tab_statistics
            WHERE  owner='${SCHEMA}'
            AND    stattype_locked IS NOT NULL
            AND    table_name NOT IN (${TABLE_LIST}))
  LOOP
      EXECUTE IMMEDIATE 'BEGIN DBMS_STATS.unlock_table_stats(''${SCHEMA}'','''||t.table_name||'''); END;';
      l_unlock_counter := l_unlock_counter + 1;
  END LOOP;
  DBMS_OUTPUT.put_line('Unlocked '||l_unlock_counter||' table statistics.');
  END;
  /
  EXIT
EOSQL
)
done

[[ $? -ne 0 ]] && error "Unlocking statistics"
info "${SQLRESULT}"

[[ ! -z "$REPOSITORY_DISPATCH" ]] && github_repository_dispatch "oracle-db-statistics-success" "${JSON_INPUTS}"
info "Completes successfully"

# Exit with success status if no error found
exit 0
