#!/bin/bash
#
# Get range of archive log sequence numbers required to support named flashback restore point.
#
# The required information is only available once a log switch has occurred.
#

. ~/.bash_profile

sqlplus -s /  as sysdba <<EOF
WHENEVER SQLERROR EXIT FAILURE;
SET FEEDBACK OFF
SET HEADING OFF
SET PAGES 0

ALTER SYSTEM SWITCH LOGFILE;
 /
 /
 /
 /
 EXEC DBMS_SESSION.SLEEP(30);

 SELECT MIN(al.sequence#)||','||MAX(al.sequence#)
    FROM v\$archived_log al,
         (select grsp.rspfscn               from_scn,
                 grsp.rspscn                to_scn,
                 dbinc.resetlogs_change#    resetlogs_change#,
                 dbinc.resetlogs_time       resetlogs_time,
                 grsp.rspname               rspname
            from x\$kccrsp grsp,  v\$database_incarnation dbinc
           where grsp.rspincarn = dbinc.incarnation#
             and bitand(grsp.rspflags, 2) != 0
             and bitand(grsp.rspflags, 1) = 1 -- guaranteed
             and grsp.rspfscn <= grsp.rspscn -- filter clean grp
             and grsp.rspfscn != 0
             and grsp.rspname='${RESTORE_POINT_NAME}'
         ) grsp
      WHERE al.next_change#   >= grsp.from_scn
          AND al.first_change#    <= (grsp.to_scn + 1)
          AND al.resetlogs_change# = grsp.resetlogs_change#
          AND al.resetlogs_time       = grsp.resetlogs_time
          AND al.archived = 'YES';

EOF