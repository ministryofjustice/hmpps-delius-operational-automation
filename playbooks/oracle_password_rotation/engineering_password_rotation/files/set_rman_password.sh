#!/bin/bash

. ~/.bash_profile

sqlplus /nolog <<EOSQL
connect / as sysdba
alter user rman19c identified by ${RMAN_PASSWORD};
exit;
EOSQL
