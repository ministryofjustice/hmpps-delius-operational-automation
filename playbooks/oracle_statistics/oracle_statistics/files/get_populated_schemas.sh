#!/bin/bash
#
#  Take a List of Schemas and Return List of Those Which Contain Segments
#

OWNERS_LIST=$1

. ~/.bash_profile

sqlplus -s /nolog <<EOSQL
connect / as sysdba

DEFINE OWNERS=${OWNERS_LIST}

WHENEVER SQLERROR EXIT FAILURE
SET FEEDBACK OFF
SET SERVEROUT ON
SET HEADING OFF
SET PAGES 0

SELECT owner
FROM   dba_tables
WHERE  owner IN (${OWNERS_LIST})  
UNION
SELECT owner
FROM   dba_indexes
WHERE  owner IN (${OWNERS_LIST});

EXIT
EOSQL