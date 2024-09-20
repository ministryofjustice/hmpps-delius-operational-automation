#!/bin/bash
# If we are restarting after a refresh, flashback or restore we need to start
# replicating user data (including probation_area_user) that is newer than the
# data in the client database.   We find the most recent update in the data
# from either the USER_ or the PROBATION_AREA_USER table and use that as a lower
# limit on data to be replicated from the Repository to the Client
. ~/.bash_profile
sqlplus -s / as sysdba <<EOSQL
SET HEAD OFF
SET FEED OFF
SET PAGES 0
SELECT REPLACE(TO_CHAR(SYS_EXTRACT_UTC(CAST(MAX(last_updated_datetime) AS TIMESTAMP)),
                    'YYYY-MM-DD HH24:MI:SS'),
            ' ',
            'T')
FROM
    (
        SELECT
            MAX(last_updated_datetime) last_updated_datetime
        FROM
            delius_app_schema.user_
        UNION ALL
        SELECT
            MAX(last_updated_datetime)
        FROM
            delius_app_schema.probation_area_user
    );
EXIT
EOSQL