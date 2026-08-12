#!/bin/bash

THISSCRIPT=${THISSCRIPT:-$(basename "$0")}
INFO_LOG_FILE=${INFO_LOG_FILE:-/tmp/run_backup_validation_info$$.log}
RUN_LOG_FILE=${RUN_LOG_FILE:-/tmp/run_backup_validation_run$$.log}

info() {
  T=$(date +"%D %T")
  echo "INFO : ${THISSCRIPT} : $T : $1" >> "$INFO_LOG_FILE"
}

init_run_logging() {
  mkdir -p "$(dirname "$RUN_LOG_FILE")"
  touch "$RUN_LOG_FILE"
  exec > >(tee -a "$RUN_LOG_FILE") 2>&1
  echo "INFO : ${THISSCRIPT} : $(date +"%D %T") : Logging script output to ${RUN_LOG_FILE}"
}

validate_regex() {
  local value="$1"
  local regex="$2"
  local field_name="$3"

  if [[ ! "$value" =~ $regex ]]; then
    echo "ERROR : ${THISSCRIPT} : $(date +"%D %T") : Invalid ${field_name}: ${value}" >&2
    exit 1
  fi
}

escape_rman_single_quotes() {
  # RMAN string literals use single quotes; escape embedded single quotes by doubling.
  printf '%s' "$1" | sed "s/'/''/g"
}

get_rman_password () {
  validate_regex "${ASSUME_ROLE_NAME:-}" '^[A-Za-z0-9+=,.@_-]{1,128}$' 'ASSUME_ROLE_NAME'
  validate_regex "${SECRET_ACCOUNT_ID:-}" '^[0-9]{12}$' 'SECRET_ACCOUNT_ID'

  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ASSUME_ROLE_NAME}"
  SESSION="catalog-ansible"
  CREDS_JSON=$(aws sts assume-role --role-arn "${ROLE_ARN}" --role-session-name "${SESSION}" --duration-seconds 900 --output json)
  export AWS_ACCESS_KEY_ID=$(jq -r '.Credentials.AccessKeyId' <<< "$CREDS_JSON")
  export AWS_SECRET_ACCESS_KEY=$(jq -r '.Credentials.SecretAccessKey' <<< "$CREDS_JSON")
  export AWS_SESSION_TOKEN=$(jq -r '.Credentials.SessionToken' <<< "$CREDS_JSON")

  validate_regex "${AWS_ACCESS_KEY_ID}" '^ASIA[0-9A-Z]{16}$' 'AWS_ACCESS_KEY_ID'
  validate_regex "${AWS_SECRET_ACCESS_KEY}" '^[A-Za-z0-9/+=]{40}$' 'AWS_SECRET_ACCESS_KEY'
  validate_regex "${AWS_SESSION_TOKEN}" '^[A-Za-z0-9/+=._-]{100,}$' 'AWS_SESSION_TOKEN'

  ASSUMED_ARN=$(aws sts get-caller-identity --query Arn --output text)
  if [[ "$ASSUMED_ARN" != *":assumed-role/${ASSUME_ROLE_NAME}/"* ]]; then
    echo "ERROR : ${THISSCRIPT} : $(date +"%D %T") : Unexpected assumed role identity ${ASSUMED_ARN}" >&2
    exit 1
  fi

  SECRET_ARN="arn:aws:secretsmanager:eu-west-2:${SECRET_ACCOUNT_ID}:secret:${SECRET}"
  RMANPASS=$(aws secretsmanager get-secret-value --secret-id "${SECRET_ARN}" --query SecretString --output text | jq -r .rcvcatowner)
}

create_client_payload() {
# Create a payload for Repository Dispatch events from environment variables.
  sanitize_value() {
    local value="$1"
    local regex="$2"
    local fallback="$3"

    # Keep values single-line to avoid downstream output or log injection.
    value=$(printf '%s' "$value" | tr -d '\r\n')
    if [[ "$value" =~ $regex ]]; then
      printf '%s' "$value"
    else
      printf '%s' "$fallback"
    fi
  }

  local safe_target_environment
  local safe_target_host
  local safe_source_code_version
  local safe_source_config_version

  safe_target_environment=$(sanitize_value "${TARGET_ENVIRONMENT:-unknown}" '^[a-z0-9-]+$' 'unknown')
  safe_target_host=$(sanitize_value "${TARGET_HOST:-unknown}" '^[A-Za-z0-9._-]+$' 'unknown')
  safe_source_code_version=$(sanitize_value "${SOURCE_CODE_VERSION:-main}" '^[A-Za-z0-9._/-]+$' 'main')
  safe_source_config_version=$(sanitize_value "${SOURCE_CONFIG_VERSION:-main}" '^[A-Za-z0-9._/-]+$' 'main')

  CLIENT_PAYLOAD=$(jq -n \
    --arg target_environment "$safe_target_environment" \
    --arg target_host "$safe_target_host" \
    --arg source_code_version "$safe_source_code_version" \
    --arg source_config_version "$safe_source_config_version" \
    --arg dispatch_source "oracle-backup-validation" \
    '{
      TargetEnvironment: $target_environment,
      TargetHost: $target_host,
      SourceCodeVersion: $source_code_version,
      SourceConfigVersion: $source_config_version,
      DispatchSource: $dispatch_source
    }')
}

ORACLE_SID="$1"
START_SCN="$2"
PARALLELISM="$3"
VALIDATE_INCREMENTAL_COMMAND="$4"
VALIDATE_ARCHIVELOG_COMMAND="$5"
END_SCN="$6"

init_run_logging

TARGET_ENVIRONMENT="${TARGET_ENVIRONMENT:-unknown}"
TARGET_HOST="${TARGET_HOST:-unknown}"
SOURCE_CODE_VERSION="${SOURCE_CODE_VERSION:-main}"
SOURCE_CONFIG_VERSION="${SOURCE_CONFIG_VERSION:-main}"

validate_regex "$ORACLE_SID" '^[A-Za-z0-9_]+$' 'ORACLE_SID'
validate_regex "$START_SCN" '^[0-9]+$' 'START_SCN'
validate_regex "$PARALLELISM" '^[0-9]+$' 'PARALLELISM'

if [[ -n "$END_SCN" ]]; then
  validate_regex "$END_SCN" '^[0-9]+$' 'END_SCN'
fi

# Validate command fragments that are later interpolated into the RMAN heredoc.
if [[ ! "$VALIDATE_INCREMENTAL_COMMAND" =~ ^validate\ backupset\ [0-9,]+\;$ && ! "$VALIDATE_INCREMENTAL_COMMAND" =~ ^#\ No\ Incrementals\ to\ Validate$ ]]; then
  echo "ERROR : ${THISSCRIPT} : $(date +"%D %T") : Invalid VALIDATE_INCREMENTAL_COMMAND" >&2
  exit 1
fi

if [[ ! "$VALIDATE_ARCHIVELOG_COMMAND" =~ ^validate\ backupset\ [0-9,]+\;$ && ! "$VALIDATE_ARCHIVELOG_COMMAND" =~ ^#\ No\ Archivelog\ Backups\ to\ Validate$ ]]; then
  echo "ERROR : ${THISSCRIPT} : $(date +"%D %T") : Invalid VALIDATE_ARCHIVELOG_COMMAND" >&2
  exit 1
fi

export ORACLE_SID
export START_SCN
export PARALLELISM
export VALIDATE_INCREMENTAL_COMMAND
export VALIDATE_ARCHIVELOG_COMMAND
export END_SCN
export TARGET_ENVIRONMENT
export TARGET_HOST
export SOURCE_CODE_VERSION
export SOURCE_CONFIG_VERSION
export RUN_LOG_FILE

export PATH="$PATH:/usr/local/bin"
export ORAENV_ASK="NO"
. oraenv >/dev/null;

VALIDATE_RESTORE_CONTROLFILE_COMMAND="restore controlfile validate;"
VALIDATE_RESTORE_DATABASE_COMMAND="restore database validate;"
VALIDATE_RESTORE_ARCHIVELOG_COMMAND="restore archivelog from scn ${START_SCN} validate;"

# Check end SCN 
if [[ -n "$END_SCN" ]]
then
    VALIDATE_RESTORE_CONTROLFILE_COMMAND="restore controlfile until scn ${END_SCN} validate;"
    VALIDATE_RESTORE_DATABASE_COMMAND="restore database until scn ${END_SCN} validate;"
    VALIDATE_RESTORE_ARCHIVELOG_COMMAND="restore archivelog from scn ${START_SCN} until scn ${END_SCN} validate;"
fi

# We perform 3 different validations:
# (1) Validate that a control file may be restored.
# (2) Validate that the database may be restored.
# (3) Validate that incremental backupsets may be restored (pass in the validation command)
# (4) Validate that archive log backupsets may be restored after the given SCN (pass in the validation command)
# (5) Validate that archive logs may be restored after the given SCN (which should be the start SCN for the database backup)
#

if [[ "${CATALOG:-NOCATALOG}" != "NOCATALOG" ]]
then
   get_rman_password
  escaped_rmanpass="$(escape_rman_single_quotes "${RMANPASS}")"
  escaped_catalog="$(escape_rman_single_quotes "${CATALOG}")"
  CONNECT_TO_CATALOG="connect catalog 'rcvcatowner/${escaped_rmanpass}@${escaped_catalog}'"
fi

# shellcheck source=../../common/files/github_dispatch.sh
LOG_FILE="/tmp/rman_validation$$.log"
EVENT_TYPE="oracle-db-backup-validation-failure"

_dispatch_lib="$(dirname "$0")/github_dispatch.sh"
if ! source "$_dispatch_lib"; then
  echo "ERROR : $THISSCRIPT : $(date +"%D %T") : Failed to source $_dispatch_lib" | tee "$LOG_FILE"
else
  rman target / <<EOF  | tee "$LOG_FILE"
set echo on
${CONNECT_TO_CATALOG}
configure device type 'SBT_TAPE' parallelism ${PARALLELISM};
${VALIDATE_RESTORE_CONTROLFILE_COMMAND}
${VALIDATE_RESTORE_DATABASE_COMMAND}
${VALIDATE_INCREMENTAL_COMMAND}
${VALIDATE_ARCHIVELOG_COMMAND}
${VALIDATE_RESTORE_ARCHIVELOG_COMMAND}
exit
EOF

  RMAN_RC=${PIPESTATUS[0]}
  if [[ $RMAN_RC -eq 0 ]] && ! grep -Eq 'ORA-|ERROR MESSAGE STACK FOLLOWS' "$LOG_FILE"; then
    EVENT_TYPE="oracle-db-backup-validation-success"
  fi

  create_client_payload
  github_repository_dispatch "$EVENT_TYPE" "$CLIENT_PAYLOAD"
fi

unset _dispatch_lib
 