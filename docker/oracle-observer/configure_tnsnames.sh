#!/bin/bash

. ~/.bash_profile

# Check if required environment variables are set
if [ -z "$PRIMARYDB_HOSTNAME" ]; then
  echo "Error: PRIMARYDB_HOSTNAME is not set."
  exit 1
fi

if [ -z "$DATABASE_PORT" ]; then
  echo "Error: DATABASE_PORT is not set."
  exit 1
fi

if [ -z "$DATABASE_NAME" ]; then
  echo "Error: DATABASE_NAME is not set."
  exit 1
fi

# Treat standby database environment variables as "none" if not set
STANDBYDB1_HOSTNAME=${STANDBYDB1_HOSTNAME:-none}
STANDBYDB2_HOSTNAME=${STANDBYDB2_HOSTNAME:-none}

# Path to tnsnames.ora file
tnsnames_file="${ORACLE_HOME}/network/admin/tnsnames.ora"

# Create the tnsnames.ora file
cat <<EOL > "$tnsnames_file"
$DATABASE_NAME =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = $PRIMARYDB_HOSTNAME)(PORT = $DATABASE_PORT))
    (CONNECT_DATA =
      (SERVICE_NAME = $DATABASE_NAME)
    )
  )
EOL

# Add standby databases if they exist
if [ "$STANDBYDB1_HOSTNAME" != "none" ]; then
  cat <<EOL >> "$tnsnames_file"
${DATABASE_NAME}S1 =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = $STANDBYDB1_HOSTNAME)(PORT = $DATABASE_PORT))
    (CONNECT_DATA =
      (SERVICE_NAME = ${DATABASE_NAME}S1)
    )
  )
EOL
fi

if [ "$STANDBYDB2_HOSTNAME" != "none" ]; then
  cat <<EOL >> "$tnsnames_file"
${DATABASE_NAME}S2 =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = $STANDBYDB2_HOSTNAME)(PORT = $DATABASE_PORT))
    (CONNECT_DATA =
      (SERVICE_NAME = ${DATABASE_NAME}S2)
    )
  )
EOL
fi