#!/bin/bash

. ~/.bash_profile
PATH=$PATH:/usr/local/bin
export ORACLE_SID="${CATALOG_DB}"
export ORAENV_ASK=NO
. oraenv
TEMP_IMPORT_PASSWORD="$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 20)"

# Due to undiagnosed problem with ORA-02153: invalid VALUES password string
# importing the user, pre-create it with a valid password
sqlplus / as sysdba <<EOF
CREATE USER ${EXPORT_NAME} IDENTIFIED BY p${TEMP_IMPORT_PASSWORD}# DEFAULT TABLESPACE rcvcat_${SOURCE_CATALOG_DB}_tbs TEMPORARY TABLESPACE temp;
EOF

impdp \"/ as sysdba\" dumpfile=${EXPORT_NAME}.dmp logfile=${EXPORT_NAME}.import.log schemas=rcvcatowner job_name=${EXPORT_NAME} remap_schema=rcvcatowner:${EXPORT_NAME} remap_tablespace=rcvcat_tbs:rcvcat_${SOURCE_CATALOG_DB}_tbs directory=DATA_PUMP_DIR