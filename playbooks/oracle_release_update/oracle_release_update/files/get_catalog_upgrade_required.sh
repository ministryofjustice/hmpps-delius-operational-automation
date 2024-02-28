#!/bin/bash

# Determine if an RMAN Catalog Upgrade is required

. ~/.bash_profile

CATALOG_PASSWORD=$(aws ssm get-parameters --region ${REGION} --with-decryption --name ${SSM_NAME} | jq -r '.Parameters[].Value')

rman <<EORMAN
connect catalog rman19c/${CATALOG_PASSWORD}
exit;
EORMAN