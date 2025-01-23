#!/bin/bash

. ~/.bash_profile
OBSERVER_DIR=/u01/app/oracle/dg_observer
mkdir ${OBSERVER_DIR}

# We first stop any previous observers in the configuration which may have been left
# inactive from a previous task run.
# We start the observer in foreground mode; this keeps the docker container active
dgmgrl /@${DATABASE_NAME} <<EOL
stop observer all;
start observer file is '${OBSERVER_DIR}/dg_broker.ora' logfile is '${OBSERVER_DIR}/dg_broker.log';
EOL