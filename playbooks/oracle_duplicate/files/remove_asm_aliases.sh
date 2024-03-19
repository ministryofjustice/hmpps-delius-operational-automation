#!/bin/bash
#
#  When duplicating from non-ASM to ASM we end up with aliases to the actual
#  files in ASM, rather than the files themselves.   Whilst this avoids
#  Oracle having to update the controlfile with new locations if can create
#  further problems later with migrations and does not comply with
#  expected naming conventions.
#
#  Therefore we ensure that files are accessed directly on ASM and not
#  via aliases (which will be removed)
#
#  Note that if we are duplicating from a database which is using ASM
#  then this script will have no actions to perform as it will not be
#  using aliases.
#
#

. ~/.bash_profile


sqlplus / as sysdba <<EOSQL

SET ECHO OFF
SET TIMING ON
SET FEEDBACK ON
SET TERMOUT ON
SET SERVEROUT ON

spool /tmp/remove_asm_aliases.log


BEGIN
FOR x IN (SELECT table_name
          FROM   dba_tables
          WHERE  owner = 'SYSTEM'
          AND    table_name = 'Z_ASM_ALIASES')
LOOP
   DBMS_OUTPUT.put_line('DROP TABLE system.z_asm_aliases');
   EXECUTE IMMEDIATE 'DROP TABLE system.z_asm_aliases';
END LOOP;
END;
/


CREATE TABLE system.z_asm_aliases
(
full_alias_path varchar2(1000) not null,
actual_name     varchar2(1000),
file_type       varchar2(30)
);


-- We use SYSTEM CREATED = 'N' flag to identify aliases being used for datafiles, tempfiles or onlinelogs
INSERT INTO system.z_asm_aliases
with asm_aliases
as (
select file_number,concat('+'||gname, sys_connect_by_path(aname, '/')) full_alias_path,
       system_created, alias_directory, file_type
from ( select a.file_number, b.name gname, a.parent_index pindex, a.name aname,
              a.reference_index rindex , a.system_created, a.alias_directory,
              c.type file_type
       from v\$asm_alias a
       left join v\$asm_diskgroup b
       on a.group_number = b.group_number
       left join v\$asm_file c
       on a.group_number = c.group_number
       and a.file_number = c.file_number
       and a.file_incarnation = c.incarnation
     )
start with (mod(pindex, power(2, 24))) = 0
            and rindex in
                ( select a.reference_index
                  from v\$asm_alias a
                  inner join v\$asm_diskgroup b
                  on a.group_number = b.group_number
                )
connect by prior rindex = pindex
)
select a1.full_alias_path alias_name,a2.full_alias_path actual_name,a1.file_type
from asm_aliases a1
left join asm_aliases a2
on a2.system_created='Y'
and a1.file_number=a2.file_number
left join dba_data_files f
on a1.full_alias_path = f.file_name
where a1.system_created='N'
and a1.file_type is not null
;

-- To eliminate DATAFILE aliases we must move these within their existing disk groups
-- See:  ORA-01523 WHILE RENAMING ORACLE FILE FROM ASM ALIAS TO FULLY QUALIFIED NAME (Doc ID 1967964.1)
BEGIN
FOR x IN (SELECT     file_id
          FROM       system.z_asm_aliases a
          INNER JOIN dba_data_files f
          ON         a.full_alias_path = f.file_name
          WHERE      a.file_type = 'DATAFILE'
          ORDER BY   f.file_id)
LOOP
   DBMS_OUTPUT.put_line('ALTER DATABASE MOVE DATAFILE '||x.file_id);
   EXECUTE IMMEDIATE 'ALTER DATABASE MOVE DATAFILE '||x.file_id;
END LOOP;
END;
/

-- To eliminate TEMPFILE aliases we must add new tempfiles and drop the original ones
-- (1) Add new tempfiles
BEGIN
FOR x IN (SELECT     'ALTER TABLESPACE '||f.tablespace_name||' ADD TEMPFILE '''||SUBSTR(full_alias_path,0,INSTR(full_alias_path,'/')-1)||''' SIZE '||f.bytes||
                     CASE f.autoextensible WHEN 'YES' THEN ' AUTOEXTEND ON NEXT '||f.increment_by*t.block_size||' MAXSIZE '||f.maxbytes ELSE '' END run_cmd
          FROM       system.z_asm_aliases a
          INNER JOIN dba_temp_files f
          ON         a.full_alias_path = f.file_name
          INNER JOIN dba_tablespaces t
          ON         f.tablespace_name = t.tablespace_name
          WHERE a.file_type = 'TEMPFILE')
LOOP
   DBMS_OUTPUT.put_line(x.run_cmd);
   EXECUTE IMMEDIATE x.run_cmd;
END LOOP;
END;
/

-- (2) Take existing tempfiles offline
BEGIN
FOR x IN (SELECT full_alias_path
          FROM   system.z_asm_aliases
          WHERE  file_type = 'TEMPFILE')
LOOP
   DBMS_OUTPUT.put_line('ALTER DATABASE TEMPFILE '''||x.full_alias_path||''' OFFLINE');
   EXECUTE IMMEDIATE 'ALTER DATABASE TEMPFILE '''||x.full_alias_path||''' OFFLINE';
END LOOP;
END;
/

-- (3) Kill any sessions using TEMP space
--     As we are still setting up the database there should not be any
BEGIN
FOR x IN (SELECT     sid,serial#
          FROM       v\$sort_usage u
          INNER JOIN v\$session s
          ON         u.session_addr = s.saddr
          WHERE EXISTS (SELECT 1 
                        FROM   system.z_asm_aliases
                        WHERE  file_type = 'TEMPFILE'))
LOOP
   DBMS_OUTPUT.put_line('ALTER SYSTEM KILL SESSION '''||x.sid||','||x.serial#||''' IMMEDIATE');
   EXECUTE IMMEDIATE 'ALTER SYSTEM KILL SESSION '''||x.sid||','||x.serial#||''' IMMEDIATE';
END LOOP;
END;
/

-- (4) Drop existing (now replaced) tempfiles
BEGIN
FOR x IN (SELECT full_alias_path
          FROM   system.z_asm_aliases
          WHERE  file_type = 'TEMPFILE')
LOOP
   DBMS_OUTPUT.put_line('ALTER DATABASE TEMPFILE '''||x.full_alias_path||''' DROP INCLUDING DATAFILES');
   EXECUTE IMMEDIATE 'ALTER DATABASE TEMPFILE '''||x.full_alias_path||''' DROP INCLUDING DATAFILES';
END LOOP;
END;
/


-- Add Replacement Online Redo Logs
-- (1) Add New Groups (account for any non-aliased members already in existence)
DECLARE
   l_disk_groups              VARCHAR2(30);
   l_highest_group            INTEGER;
   l_number_of_groups         INTEGER;
   l_number_of_aliased_groups INTEGER;
   l_size_bytes               INTEGER;
BEGIN
SELECT LISTAGG(DISTINCT ''''||SUBSTR(a.full_alias_path,0,instr(full_alias_path,'/')-1)||'''',',') disk_groups
           ,MAX(l.group#) highest_group
           ,COUNT(DISTINCT CASE WHEN full_alias_path IS NOT NULL THEN l.group# ELSE NULL END) number_of_aliased_groups
           ,COUNT(DISTINCT l.group#) number_of_groups
           ,MAX(l.bytes) size_bytes
INTO        l_disk_groups
           ,l_highest_group
           ,l_number_of_aliased_groups
           ,l_number_of_groups
           ,l_size_bytes
FROM   v\$logfile f
LEFT JOIN system.z_asm_aliases a
ON f.member = a.full_alias_path
INNER JOIN v\$log l
ON         f.group# = l.group#;
FOR x IN l_highest_group+1..(l_highest_group+(2*l_number_of_aliased_groups)-l_number_of_groups)
LOOP
   DBMS_OUTPUT.put_line('ALTER DATABASE ADD LOGFILE GROUP '||x||' ('||l_disk_groups||') SIZE '||l_size_bytes);
   EXECUTE IMMEDIATE 'ALTER DATABASE ADD LOGFILE GROUP '||x||' ('||l_disk_groups||') SIZE '||l_size_bytes;
END LOOP;
END;
/

-- (2) Drop Old Redo Groups
DECLARE
   e_crash_recovery EXCEPTION;
   e_current_log    EXCEPTION;
   e_needs_archived EXCEPTION;
   PRAGMA EXCEPTION_INIT(e_crash_recovery,-1624);
   PRAGMA EXCEPTION_INIT(e_current_log,-1623);
   PRAGMA EXCEPTION_INIT(e_needs_archived,-350);
   l_logfile_group INTEGER;
PROCEDURE drop_log_group(p_group_number INTEGER)
AS
BEGIN
    DBMS_OUTPUT.put_line('ALTER SYSTEM CHECKPOINT');
    EXECUTE IMMEDIATE 'ALTER SYSTEM CHECKPOINT';
    DBMS_OUTPUT.put_line('ALTER SYSTEM SWITCH LOGFILE');
    EXECUTE IMMEDIATE 'ALTER SYSTEM SWITCH LOGFILE';
    DBMS_OUTPUT.put_line('ALTER DATABASE DROP LOGFILE GROUP '||p_group_number);
    EXECUTE IMMEDIATE 'ALTER DATABASE DROP LOGFILE GROUP '||p_group_number;
END;
BEGIN
FOR x IN (SELECT     DISTINCT f.group#
          FROM       system.z_asm_aliases a
          INNER JOIN v\$logfile f
          ON         a.full_alias_path = f.member
          INNER JOIN v\$log l
          ON         f.group# = l.group#
          ORDER BY   f.group#)
LOOP
   BEGIN
       l_logfile_group := x.group#;
       drop_log_group(l_logfile_group);
   EXCEPTION
   WHEN e_crash_recovery OR e_current_log OR e_needs_archived
   THEN
      drop_log_group(l_logfile_group);
   END;
END LOOP;
END;
/

-- (3) Delete Dropped Redo Log Files (this also clears up the aliases)
BEGIN
FOR x IN (SELECT SUBSTR(full_alias_path,2,INSTR(full_alias_path,'/')-2) diskgroup,actual_name
          FROM   system.z_asm_aliases a
          WHERE file_type = 'ONLINELOG')
LOOP
   DBMS_OUTPUT.put_line('ALTER DISKGROUP '||x.diskgroup||' DROP FILE '''||x.actual_name||'''');
   EXECUTE IMMEDIATE 'ALTER DISKGROUP '||x.diskgroup||' DROP FILE '''||x.actual_name||'''';
END LOOP;
END;
/


DROP TABLE system.z_asm_aliases;

spool off

EOSQL
