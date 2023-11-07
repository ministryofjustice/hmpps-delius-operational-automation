#!/bin/bash

. ~/.bash_profile

[[ ! -z "$CATALOG_CONNECTION" ]] && CONNECT_CATALOG="connect catalog ${CATALOG_CONNECTION}"

rman target / <<EORMAN

$CONNECT_CATALOG

set echo on

run {
  FLASHBACK DATABASE TO RESTORE POINT ${RESTORE_POINT_NAME};
  }

EORMAN