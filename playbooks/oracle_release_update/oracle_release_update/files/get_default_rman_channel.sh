#!/bin/bash

# Get the default tape device to use 

. ~/.bash_profile

rman target / <<EORMAN | grep "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS" | awk -F= '{print $NF}' | tr -d ")';"
SHOW CHANNEL;
exit;
EORMAN