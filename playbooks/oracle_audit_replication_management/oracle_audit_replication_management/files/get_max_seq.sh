#!/bin/bash

# Get highest numbered archived log

. ~/.bash_profile

sqlplus -S -L /nolog <<EOSQL
connect / as sysdba
SET HEAD OFF
SET TRIMSPOOL ON
SET PAGES 0
SET FEEDBACK OFF

COL max_seq FORMAT FM99999990

SELECT
    MAX(sequence#) max_seq
FROM
    v\$archived_log
WHERE
        dest_id = 1
    AND resetlogs_time = (
        SELECT
            resetlogs_time
        FROM
            v\$database
    );

EXIT
EOSQL