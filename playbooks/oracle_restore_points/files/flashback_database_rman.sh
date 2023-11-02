#!/bin/bash

. ~/.bash_profile

rman target / <<EORMAN

connect catalog ${CATALOG_CONNECTION}

set echo on

run {
  FLASHBACK DATABASE TO RESTORE POINT ${RESTORE_POINT_NAME};
  }

EORMAN