#!/bin/bash

. ~/.bash_profile

sqlplus -s /  as sysdba <<EOF
SET LINES 1000
SET PAGES 0
SET FEEDBACK OFF
SET HEADING OFF
WHENEVER SQLERROR EXIT FAILURE
CREATE TABLESPACE statspack_data
DATAFILE '+DATA' 
SIZE 1G 
AUTOEXTEND ON MAXSIZE 4G;
EXIT
EOF