#!/bin/bash

. ~/.bash_profile
WALLET_DIR="$ORACLE_HOME/network/admin/wallet"

# Remove existing wallet if it exists
if [ -d "$WALLET_DIR" ]; then
    echo "Removing existing wallet directory at $WALLET_DIR..."
    rm -rf "$WALLET_DIR"
fi

# Create wallet directory
echo "Creating wallet directory at $WALLET_DIR..."
mkdir -p "$WALLET_DIR"
chmod 700 "$WALLET_DIR"

# Retrieve the SYS password from AWS Secrets Manager
echo "Retrieving SYS password from AWS Secrets Manager..."
SYS_PASSWORD=$(aws secretsmanager get-secret-value \
               --secret-id "${SECRET_ID}" \
               --region eu-west-2 --query 'SecretString' \
               --output json | jq -r '.' | jq -r '.sys')

if [ -z "$SYS_PASSWORD" ]; then
    echo "Failed to retrieve the SYS password. Please check your AWS CLI configuration and secret name."
    exit 1
fi

# Navigate to the wallet directory
cd "$WALLET_DIR" || exit 1

# Create an auto-login only Oracle wallet using orapki
echo "Creating auto-login only Oracle wallet with orapki..."
$ORACLE_HOME/bin/orapki wallet create -wallet "$WALLET_DIR" -auto_login_only

# Add SYS password to the wallet for the ABCDEF database
echo "Adding SYS password to the Oracle wallet for the ABCDEF database..."
$ORACLE_HOME/bin/orapki wallet add -wallet "$WALLET_DIR" -dbalias "$DB_ALIAS" -user "SYS" -password "$SYS_PASSWORD"

# Verify the wallet contents
echo "Verifying wallet contents..."
$ORACLE_HOME/bin/orapki wallet display -wallet "$WALLET_DIR"

# Clean up sensitive data
unset SYS_PASSWORD

# Success message
echo "Auto-login only Oracle wallet successfully created and SYS password added for the ABCDEF database."
