#!/bin/bash

. ~/.bash_profile
WALLET_DIR="/u01/app/oracle/wallets"

# Remove existing wallet if it exists
if [ -d "$WALLET_DIR" ]; then
    echo "Removing existing wallet directory at $WALLET_DIR..."
    rm -rf "$WALLET_DIR"
fi

# Create wallet directory
echo "Creating wallet directory at $WALLET_DIR..."
mkdir -p "$WALLET_DIR"
chmod 700 "$WALLET_DIR"

SYS_PASSWORD=$(echo ${DATABASE_SECRETS_JSON} | jq -r '.sys')

if [ -z "$SYS_PASSWORD" ]; then
    echo "Failed to find the SYS password."
    exit 1
fi

# Navigate to the wallet directory
cd "$WALLET_DIR" || exit 1

# Create an auto-login only Oracle wallet using orapki
echo "Creating auto-login only Oracle wallet with orapki..."
$ORACLE_HOME/bin/orapki wallet create -wallet "$WALLET_DIR" -auto_login_only

# Add SYS password to the wallet for the target database
echo "Adding SYS password to the Oracle wallet for the ${DATABASE_NAME} database..."
$ORACLE_HOME/bin/orapki wallet add -wallet "$WALLET_DIR" -dbalias "${DATABASE_NAME}" -user "SYS" -password "$SYS_PASSWORD"

# Verify the wallet contents
echo "Verifying wallet contents..."
$ORACLE_HOME/bin/orapki wallet display -wallet "$WALLET_DIR"

# Clean up sensitive data
unset SYS_PASSWORD

# Success message
echo "Auto-login only Oracle wallet successfully created and SYS password added for the ABCDEF database."
