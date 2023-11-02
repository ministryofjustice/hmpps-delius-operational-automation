#!/bin/bash
#
# Remove KEEP attribute from backup (allow normal recovery window to apply)
#
. ~/.bash_profile

rman target / <<EORMAN

connect catalog ${CATALOG_CONNECTION}

change backup tag='RP_${RESTORE_POINT_NAME}' nokeep;

EORMAN