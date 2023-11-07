#!/bin/bash
#
# Remove KEEP attribute from backup (allow normal recovery window to apply)
#
. ~/.bash_profile

[[ ! -z "$CATALOG_CONNECT " ]] && CONNECT_CATALOG="connect catalog ${CATALOG_CONNECTION}"

rman target / <<EORMAN

$CONNECT_CATALOG

change backup tag='RP_${RESTORE_POINT_NAME}' nokeep;

EORMAN