#!/bin/bash
# Shared functions for authenticating to GitHub via the HMPPS Bot and sending repository dispatch events.
# Source this file from any script that needs to trigger GitHub Actions workflows.
#
# Callers may optionally define the following before sourcing:
#   info()                 - logging function; defaults to a timestamped echo to stderr
#   update_ssm_parameter() - called on dispatch failure; defaults to a no-op
#   THISSCRIPT             - script name used in error messages; defaults to basename of $0

# Default info implementation used when the caller has not defined one.
if ! declare -f info > /dev/null 2>&1; then
  info() {
    T=$(date +"%D %T")
    echo "INFO : ${THISSCRIPT:-$(basename "$0")} : $T : $1" >&2
  }
fi

# Default no-op so the dispatch function can always call it safely.
if ! declare -f update_ssm_parameter > /dev/null 2>&1; then
  update_ssm_parameter() { :; }
fi

validate_regex() {
  local value="$1"
  local regex="$2"
  local field_name="$3"

  if [[ ! "$value" =~ $regex ]]; then
    echo "ERROR : ${THISSCRIPT:-$(basename "$0")} : $(date +"%D %T") : Invalid ${field_name}" >&2
    return 1
  fi
}

require_non_empty() {
  local value="$1"
  local field_name="$2"

  if [[ -z "${value//[[:space:]]/}" ]]; then
    echo "ERROR : ${THISSCRIPT:-$(basename "$0")} : $(date +"%D %T") : Missing required ${field_name}" >&2
    return 1
  fi
}

assert_dispatch_endpoint() {
  # In GitHub Actions, lock dispatch URL to this repository to prevent token misuse.
  info "Asserting GITHUB_REPOSITORY: $GITHUB_REPOSITORY"
  echo "Asserting GITHUB_REPOSITORY: $GITHUB_REPOSITORY"
  if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
    local expected_dispatch
    expected_dispatch="https://api.github.com/repos/${GITHUB_REPOSITORY}/dispatches"
    if [[ "${REPOSITORY_DISPATCH:-}" != "$expected_dispatch" ]]; then
      echo "ERROR : ${THISSCRIPT:-$(basename "$0")} : $(date +"%D %T") : Invalid REPOSITORY_DISPATCH endpoint" >&2
      return 1
    fi
  fi
}

function generate_jwt()
{
# Get a JSON Web Token to authenicate against the HMPPS Bot.
# The HMPPS bot can provide exchange this for a GitHub Token for action GitHub workflows.
BOT_APP_ID=$(aws ssm get-parameter --name "/github/hmpps_bot_app_id" --query "Parameter.Value" --with-decryption --output text)
BOT_PRIVATE_KEY=$(aws ssm get-parameter --name "/github/hmpps_bot_priv_key" --query "Parameter.Value" --with-decryption --output text)
require_non_empty "$BOT_APP_ID" "BOT_APP_ID" || return 1
require_non_empty "$BOT_PRIVATE_KEY" "BOT_PRIVATE_KEY" || return 1
validate_regex "$BOT_APP_ID" '^[0-9]+$' 'BOT_APP_ID' || return 1

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
require_non_empty "$JWT" "JWT" || return 1
# Fetch Installation ID for App in target Repository
BOT_INSTALL_ID=$(aws ssm get-parameter --name "/github/hmpps_bot_installation_id" --query "Parameter.Value" --with-decryption --output text)
require_non_empty "$BOT_INSTALL_ID" "BOT_INSTALL_ID" || return 1
validate_regex "$BOT_INSTALL_ID" '^[0-9]+$' 'BOT_INSTALL_ID' || return 1
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
#  for either oracle-db-backup-sucess or oracle-db-backup-failure events.   These are the only 2 which
#  should be used.
#  JSON_PAYLOAD is the JSON originally passed to the script using the -j switch.  This allows the
#  workflow to continue where it left off because this JSON contains the name of the environment, host
#  and period of the backup, along with any associated parameters.
EVENT_TYPE=$1
JSON_PAYLOAD=$2
assert_dispatch_endpoint || exit 1
validate_regex "$EVENT_TYPE" '^oracle-[a-z0-9-]+-(success|failure)$' 'EVENT_TYPE' || exit 1
GITHUB_TOKEN_VALUE=$(get_github_token | jq -r '.token')
require_non_empty "$GITHUB_TOKEN_VALUE" "GITHUB_TOKEN_VALUE" || exit 1

# Allow callers to omit payload; use an empty JSON object as a safe default.
if [[ -z "${JSON_PAYLOAD//[[:space:]]/}" || "$JSON_PAYLOAD" == "null" ]]; then
  JSON_PAYLOAD='{}'
fi

# We set the Phase in the JSON payload corresponding to whether the backup has succeeded or failed.
# This is informational only - it is GitHub event type (oracle-db-backup-success/failure) which
# determines what the workflow does next.
if [[ "$EVENT_TYPE" == "oracle-db-backup-success" ]]; then
  JSON_PAYLOAD=$(echo "$JSON_PAYLOAD" | jq -r '.Phase = "Backup Succeeded"')
elif [[ "$EVENT_TYPE" == "oracle-db-backup-failure" ]]; then
  JSON_PAYLOAD=$(echo "$JSON_PAYLOAD" | jq -r '.Phase = "Backup Failed"')
fi
# GitHub Actions only allows us to have 10 elements in the payload so we remove those which are
# not necessary.  In this case we remove TargetHost for backup events 
# since that is only relevant to the original backup; any retries will use RmanTarget instead.
if [[ "$EVENT_TYPE" == "oracle-db-backup-success" || "$EVENT_TYPE" == "oracle-db-backup-failure"  ]]; then
   JSON_PAYLOAD=$(echo "$JSON_PAYLOAD" | jq -r 'del(.TargetHost)')
fi
info "Repository Dispatch Payload: $JSON_PAYLOAD"
JSON_DATA="{\"event_type\": \"${EVENT_TYPE}\",\"client_payload\":${JSON_PAYLOAD}}"
info "Posting repository dispatch event"
curl -sSf -X POST -H "Accept: application/vnd.github+json" -H "Authorization: token ${GITHUB_TOKEN_VALUE}" --data-raw "${JSON_DATA}" "${REPOSITORY_DISPATCH}"
RC=$?
if [[ $RC -ne 0 ]]; then
      # We cannot use the error function for dispatch failures as it contains its own dispatch call
      T=$(date +"%D %T")
      echo "ERROR : ${THISSCRIPT:-$(basename "$0")} : $T : Failed to dispatch ${EVENT_TYPE} event to ${REPOSITORY_DISPATCH}" | tee -a ${RMANOUTPUT:-/dev/stderr}
      update_ssm_parameter  "Error" "Failed to dispatch ${EVENT_TYPE} event to ${REPOSITORY_DISPATCH}"
      exit 1
fi
}
