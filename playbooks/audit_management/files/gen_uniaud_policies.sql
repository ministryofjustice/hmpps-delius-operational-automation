-- gen_uniaud_policies.sql
--
-- (C) Oracle Corporation 2018
-- Written by Harm Joris ten Napel, Principal Database Security Specialist, Oracle Managed Cloud
--
-- Script to generate equivalents of current UNIFIED AUDIT options
-- and the NOAUDIT statements to remove the current UNIFIED AUDIT options
--
-- Also saves the non-default unified audit policy definions to the spool file for later re-use
--
-- writes two sql files:
-- uniaud_policies_set.sql : stores current settings
-- uniaud_policies_remove.sql : removes current settings (does not remove default policies)

-- Change record:
-- Version 1.0 initial version (12.1)
-- Version 2.0 Changed for roles syntax in 12.2 and 18
-- Version 2.1 Avoid  ORA-22275 on empty CLOB
-- Version 2.2 Exclude standard policies explicitly when generating drop statements
-- Version 2.3 Workaround Bug 29185232 (convert 'CALL METHOD' to 'CALL' in audit policy)
-- Version 2.4 Adapt for version 19 where audit_unified_enabled_policies.enabled_opt was removed.
-- Version 2.5 Add 3 new Oracle pre-defined Policies
-- Version 2.6 Add cleanup code for policies w/o any actions and dropped objects (Bug 28258659)
--             The cleanup code is added to file uniaud_policies_cleanup.sql which is recommended to run.

set serveroutput on
set long 100000
set lines 2000

create global temporary table unified_audit_policies_temp(policy varchar2(128), statement clob) 
on commit preserve rows;

declare
-- need clob because (default) policies can get > 32k which cannot be printed using dbms_output.put_line
policy_statement clob;
v_clob_1 clob;
v_clob_2 clob;
v_buffer varchar2(1):=';';
clob_len number;
last_char varchar2(1);
v_offset number;
begin
-- skip known default policies
for policy_rec in
(select unique policy_name from AUDIT_UNIFIED_POLICIES
where policy_name not in (
'ORA_ACCOUNT_MGMT',
'ORA_DATABASE_PARAMETER',
'ORA_SECURECONFIG',
'ORA_DV_AUDPOL',
'ORA_DV_AUDPOL2',
'ORA_RAS_POLICY_MGMT',
'ORA_RAS_SESSION_MGMT',
'ORA_LOGON_FAILURES',
'ORA_STIG_RECOMMENDATIONS',
'ORA_LOGON_LOGOFF',
'ORA_ALL_TOPLEVEL_ACTIONS',
'ORA_CIS_RECOMMENDATIONS')
order by policy_name) loop
policy_statement:= DBMS_METADATA.GET_DDL('AUDIT_POLICY',policy_rec.policy_name);
clob_len:=DBMS_LOB.GETLENGTH(policy_statement);
-- trim spaces and newlines from statement
last_char:=dbms_lob.SUBSTR(policy_statement,1,clob_len);
while last_char = ' ' or last_char=chr(10) loop
   clob_len:=clob_len-1;
   policy_statement:=dbms_lob.substr(policy_statement,clob_len,1);
   last_char:=dbms_lob.SUBSTR(policy_statement,1,clob_len);
end loop;
-- also trim leading spaces
last_char:=dbms_lob.SUBSTR(policy_statement,1,1);
while last_char = ' ' or last_char=chr(10) loop
    clob_len:=clob_len-1;
    policy_statement:=dbms_lob.substr(policy_statement,clob_len,2);
    last_char:=dbms_lob.SUBSTR(policy_statement,1,1);
end loop;
clob_len:=DBMS_LOB.GETLENGTH(policy_statement);
if clob_len > 0 then
   -- workaround Bug 29185232
   v_offset:=dbms_lob.instr(policy_statement,'CALL METHOD');
   if v_offset>0 then
      dbms_lob.createtemporary(v_clob_1,true);
      dbms_lob.createtemporary(v_clob_2,true);
      dbms_lob.copy(v_clob_1,policy_statement,v_offset+3);
      dbms_lob.copy(v_clob_2,policy_statement,clob_len-v_offset-7,1,v_offset+11);
      dbms_lob.trim(policy_statement,0);
      dbms_lob.append(policy_statement,v_clob_1);
      dbms_lob.append(policy_statement,v_clob_2);
   end if;
   dbms_lob.writeappend(policy_statement,1,v_buffer);
   insert into unified_audit_policies_temp values(policy_rec.policy_name,policy_statement);
end if;
commit;
end loop;
end;
/

-- prompt press enter to generate the statements in a spool file
-- pause
set longchunksize 100000
set long 100000
set head off
set echo off
set pagesize 0
set verify off
set feedback off
-- this creates long lines but the sql script can still be run
-- shorter lines my wrap the output of get_ddl and cut through keywords
set lines 2000

spool uniaud_policies_set.sql

prompt -- custom audit policies
select statement "-- audit policies" from unified_audit_policies_temp order by policy;

truncate table unified_audit_policies_temp;
drop table unified_audit_policies_temp;

-- This pl/sql block generaties the unified auditing audit statements it needs
-- pl/sql because audit statements with EXCEPT, BY and for roles need to be collated. 

set serveroutput on
declare
db_version varchar2(17);
audit_statement varchar2(32000):='-- audit statements';
last_user varchar2(128):='';
last_entity varchar2(128):='';
last_policy varchar2(128):='';
statements_query varchar2(8000);
type Statements_Cursor_type is ref cursor;
statements_cursor Statements_Cursor_type;
v_username varchar2(128);
v_entity_name varchar2(128);
v_policy_name varchar2(100);
v_enabled_opt varchar2(15);
v_audit_statement varchar2(32000);
v_sf varchar2(6):='';
last_sf varchar2(6):='';
last_enabled_opt varchar2(15):='';
begin
select version into db_version from v$instance;
 if substr(db_version,1,4) <> '12.1' then
    if to_number(substr(db_version,1,2)) < 19 then
       -- dbms_output.put_line('-- generating 12.2 ~ 18 syntax');
       statements_query:='select user_name, policy_name, enabled_opt, entity_name, success||
       failure, ''AUDIT POLICY ''||POLICY_NAME||'||
       'decode(USER_NAME,''ALL USERS'','' '','' ''||'|| 
       'decode(ENABLED_OPT,''INVALID'',''BY USERS WITH GRANTED ROLES'',ENABLED_OPT)||'' "''||'||
       'nvl(USER_NAME,ENTITY_NAME)||''"'')|| decode(SUCCESS||'||
       'FAILURE, ''YESYES'', '' '', ''YESNO'' , '' WHENEVER SUCCESSFUL'', ''NOYES'' , '||
       ''' WHENEVER NOT SUCCESSFUL'', ''NONO'' , '' /* metadata issue */ '')||'' ;'' statement '||
       'from audit_unified_enabled_policies order by policy_name, enabled_opt, success||failure, user_name';
    else
       -- dbms_output.put_line('-- generating 19+ syntax');
       --
       -- please note ENTITY_TYPE is redundant, it always matches as follows:
       --
       -- ENABLED_OPTION , ENTITY_TYPE
       -- ===========================
       -- BY USER        , USER
       -- BY GRANTED ROLE, ROLE
       --
       -- so we do not need to consider ENTITY_TYPE in this part
       --
       statements_query:='select entity_name, policy_name, enabled_option, success|| failure, ''AUDIT POLICY ''||POLICY_NAME||'||
       'decode(ENTITY_NAME,''ALL USERS'','' '','' ''||'||
       'decode(ENABLED_OPTION,''BY GRANTED ROLE'',''BY USERS WITH GRANTED ROLES'',''BY USER'',''BY'',''EXCEPT USER'',''EXCEPT'',ENABLED_OPTION)||'' "''||'||
       'ENTITY_NAME||''"'')|| decode(SUCCESS||'||
       'FAILURE, ''YESYES'', '' '', ''YESNO'' , '' WHENEVER SUCCESSFUL'', ''NOYES'' , '||
       ''' WHENEVER NOT SUCCESSFUL'', ''NONO'' , '' /* metadata issue */ '')||'' ;'' statement '||
       'from audit_unified_enabled_policies order by policy_name, enabled_option, success||failure, entity_name';
       -- debug
       -- dbms_output.put_line(statements_query);
    end  if;
 else
   -- dbms_output.put_line('-- generating 12.1 syntax');
   statements_query:='select user_name, policy_name, enabled_opt, success||failure, ''AUDIT POLICY ''||POLICY_NAME||'||
   'decode(USER_NAME,''ALL USERS'','' '','' ''|| ENABLED_OPT||'' "''||USER_NAME||''"'')||'||
   'decode(SUCCESS||FAILURE, ''YESYES'', '' '', ''YESNO'' , '' WHENEVER SUCCESSFUL'','||
   ' ''NOYES'' , '' WHENEVER NOT SUCCESSFUL'', ''NONO'' , '' /* metadata issue */ '')||'' ;'' statement '||
   'from audit_unified_enabled_policies order by policy_name, enabled_opt, success||failure, user_name';
 end if;
open statements_cursor for statements_query;
loop
   if substr(db_version,1,4) = '12.2'  or substr(db_version,1,2) = '18' then
       fetch statements_cursor into v_username,v_policy_name,v_enabled_opt,v_entity_name, v_sf, v_audit_statement;
   else
      fetch statements_cursor into v_username,v_policy_name,v_enabled_opt, v_sf, v_audit_statement;
   end if;
   exit when statements_cursor%NOTFOUND;
   -- please note we output or modify the statement from the previous step
   if v_policy_name||v_enabled_opt||v_sf = last_policy||last_enabled_opt||last_sf then
      -- this means we have either multiple EXCEPT, BY or INVALID lines
      -- we have sorted on enabled_opt so they cannot be interspersed
      -- add the user to the same audit statement
      if substr(v_enabled_opt,1,6) = 'EXCEPT' or substr(v_enabled_opt,1,2) = 'BY' then
         audit_statement:= replace(audit_statement,'"'||last_user||'"', '"'||last_user||'","'||v_username||'"');
      else
         -- the other ones which are for the role auditing
         audit_statement:= replace(audit_statement,'"'||last_entity||'"', '"'||last_entity||'","'||v_entity_name||'"');
      end if;
   else
      -- done, print the statement and get the next
      dbms_output.put_line(audit_statement);
      audit_statement:=v_audit_statement;
   end if;
   last_user:=v_username;
   last_policy:=v_policy_name;
   last_entity:=v_entity_name;
   last_enabled_opt:=v_enabled_opt;
   last_sf:=v_sf;
end loop;
close statements_cursor;
-- print the last statement
dbms_output.put_line(audit_statement);
end;
/

-- for AUDIT_UNIFIED_CONTEXTS view we may simply generate a statement for each row in AUDIT_UNIFIED_CONTEXTS
prompt
prompt -- audit context
select 'AUDIT CONTEXT NAMESPACE '||namespace||' ATTRIBUTES '||attribute||
decode(USER_NAME,'ALL USERS',' ',' BY "'||user_name||'"')||';'
from AUDIT_UNIFIED_CONTEXTS order by namespace,user_name, attribute;
spool off

prompt

spool uniaud_policies_remove.sql

-- Except for EXCEPT, for the noaudit statements use a similar pl/sql block as for audit.
-- Note we also include the WHENEVER [NOT] SUCCESSFUL clause which appears valid syntax
-- ref. doc. bug 29132459 - NOAUDIT DOES NOT SPECIFY USE OF WHENEVER CLAUSE

set serveroutput on
declare
db_version varchar2(17);
audit_statement varchar2(32000):='-- noaudit statements';
last_user varchar2(128):='';
last_entity varchar2(128):='';
last_policy varchar2(128):='';
statements_query varchar2(8000);
type Statements_Cursor_type is ref cursor;
statements_cursor Statements_Cursor_type;
v_username varchar2(128);
v_entity_name varchar2(128);
v_policy_name varchar2(100);
v_enabled_opt varchar2(15);
v_audit_statement varchar2(32000);
v_sf varchar2(6):='';
last_sf varchar2(6):='';
last_enabled_opt varchar2(15):='';
begin
select version into db_version from v$instance;
 if substr(db_version,1,4) <> '12.1' then
    if to_number(substr(db_version,1,2)) < 19 then
       -- dbms_output.put_line('-- generating 12.2 ~ 18 syntax');
       statements_query:='select user_name, policy_name, enabled_opt, entity_name, success||failure, ''NOAUDIT POLICY ''||POLICY_NAME||'||
       'decode(USER_NAME,''ALL USERS'','' '','' ''||'|| 
       'decode(ENABLED_OPT,''INVALID'',''BY USERS WITH GRANTED ROLES'',ENABLED_OPT)||'' "''||'||
       'nvl(USER_NAME,ENTITY_NAME)||''"'')|| decode(SUCCESS||'||
       'FAILURE, ''YESYES'', '' '', ''YESNO'' , '' WHENEVER SUCCESSFUL'', ''NOYES'' , '||
       ''' WHENEVER NOT SUCCESSFUL'', ''NONO'' , '' /* metadata issue */ '')||'' ;'' statement '||
       'from audit_unified_enabled_policies where enabled_opt <> ''EXCEPT'' order by policy_name, enabled_opt, success||failure, user_name';
    else
       -- dbms_output.put_line('-- generating 19+ syntax');
       statements_query:='select entity_name, policy_name, enabled_option, success||failure, ''NOAUDIT POLICY ''||POLICY_NAME||'||
       'decode(ENTITY_NAME,''ALL USERS'','' '','' ''||'||
       'decode(ENABLED_OPTION,''BY GRANTED ROLE'',''BY USERS WITH GRANTED ROLES'',''BY USER'',''BY'',''EXCEPT USER'',''EXCEPT'',ENABLED_OPTION)||'' "''||'||
       'ENTITY_NAME||''"'')|| decode(SUCCESS||'||
       'FAILURE, ''YESYES'', '' '', ''YESNO'' , '' WHENEVER SUCCESSFUL'', ''NOYES'' , '||
       ''' WHENEVER NOT SUCCESSFUL'', ''NONO'' , '' /* metadata issue */ '')||'' ;'' statement '||
       'from audit_unified_enabled_policies where enabled_option <> ''EXCEPT USER'' order by policy_name, enabled_option, success||failure, entity_name';
    end  if;
 else
   -- generating 12.1 syntax'
   statements_query:='select user_name, policy_name, enabled_opt, success||failure, ''NOAUDIT POLICY ''||POLICY_NAME||'||
   'decode(USER_NAME,''ALL USERS'','' '','' ''|| ENABLED_OPT||'' "''||USER_NAME||''"'')||'||
   'decode(SUCCESS||FAILURE, ''YESYES'', '' '', ''YESNO'' , '' WHENEVER SUCCESSFUL'','||
   ' ''NOYES'' , '' WHENEVER NOT SUCCESSFUL'', ''NONO'' , '' /* metadata issue */ '')||'' ;'' statement '||
   'from audit_unified_enabled_policies where enabled_opt <> ''EXCEPT'' order by policy_name, enabled_opt, success||failure, user_name';
 end if;
open statements_cursor for statements_query;
loop
   if substr(db_version,1,4) = '12.2'  or substr(db_version,1,2) = '18' then
       fetch statements_cursor into v_username,v_policy_name,v_enabled_opt,v_entity_name, v_sf, v_audit_statement;
   else
      fetch statements_cursor into v_username,v_policy_name,v_enabled_opt, v_sf, v_audit_statement;
   end if;
   exit when statements_cursor%NOTFOUND;
   -- please note we output or modify the statement from the previous step
   if v_policy_name||v_enabled_opt||v_sf = last_policy||last_enabled_opt||last_sf then
      if substr(v_enabled_opt,1,2) = 'BY' then
         audit_statement:= replace(audit_statement,'"'||last_user||'"', '"'||last_user||'","'||v_username||'"');
      else
         -- the other ones which are for the role auditing
         audit_statement:= replace(audit_statement,'"'||last_entity||'"', '"'||last_entity||'","'||v_entity_name||'"');
      end if;
   else
      -- done, print the statement and get the next
      dbms_output.put_line(audit_statement);
      audit_statement:=v_audit_statement;
   end if;
   last_user:=v_username;
   last_policy:=v_policy_name;
   last_entity:=v_entity_name;
   last_enabled_opt:=v_enabled_opt;
   last_sf:=v_sf;
end loop;
close statements_cursor;
-- print the last statement
dbms_output.put_line(audit_statement);
end;
/

set serveroutput on
declare
noaudit_statement varchar2(255);
db_version varchar2(17);
statements_query varchar2(8000);
type Statements_Cursor_type is ref cursor;
statements_cursor Statements_Cursor_type;
begin
   select version into db_version from v$instance;
   if to_number(substr(db_version,1,2)) < 19  then
      -- audit statements set with EXCEPT must be removed with one NOAUDIT statement
      statements_query:='select unique ''NOAUDIT POLICY ''||POLICY_NAME||'';'' from audit_unified_enabled_policies where enabled_opt = ''EXCEPT''';
   else
      -- version 19 syntax
      statements_query:='select unique ''NOAUDIT POLICY ''||POLICY_NAME||'';'' from audit_unified_enabled_policies where enabled_option= ''EXCEPT USER''';
   end if;
   open statements_cursor for statements_query;
   loop
      fetch statements_cursor into noaudit_statement;
      exit when statements_cursor%NOTFOUND;
      dbms_output.put_line(noaudit_statement);
   end loop;
end;
/


prompt -- noaudit context
-- same as audit
select 'NOAUDIT CONTEXT NAMESPACE '||namespace||' ATTRIBUTES '||attribute||
decode(USER_NAME,'ALL USERS',' ',' BY "'||user_name||'"')||';'
from AUDIT_UNIFIED_CONTEXTS order by namespace,user_name, attribute;

prompt -- drop non-default policies

select unique 'DROP AUDIT POLICY '||policy_name||';'
from AUDIT_UNIFIED_POLICIES where policy_name not  in (
'ORA_ACCOUNT_MGMT',
'ORA_DATABASE_PARAMETER',
'ORA_SECURECONFIG',
'ORA_DV_AUDPOL',
'ORA_DV_AUDPOL2',
'ORA_RAS_POLICY_MGMT',
'ORA_RAS_SESSION_MGMT',
'ORA_LOGON_FAILURES',
'ORA_STIG_RECOMMENDATIONS',
'ORA_LOGON_LOGOFF',
'ORA_ALL_TOPLEVEL_ACTIONS',
'ORA_CIS_RECOMMENDATIONS')
order by 'DROP AUDIT POLICY '||policy_name||';';

spool off

spool uniaud_policies_cleanup.sql

set serveroutput on
begin
   -- Cleanup situation with dropped objects in the recyclebin (ref. Bug 28258659)
   dbms_output.put_line('-- clean policies on only recyclebin objects (recommended)');
   for ua_bin in (select object_name from dba_objects where object_type='UNIFIED AUDIT POLICY' and
                  object_name not in (select policy_name from audit_unified_policies)) loop
      -- unconditionally NOAUDIT the policy since it will not result in an error
      dbms_output.put_line('NOAUDIT POLICY '||ua_bin.object_name||';');
      dbms_output.put_line('DROP AUDIT POLICY '||ua_bin.object_name||';');
   end loop;
   -- This is the softcorruption after purge as described in Bug 28258659
   dbms_output.put_line('-- clean obsolete policies with no actions (recommended)');
   for ua_bin in (select obj.object_name  from dba_objects obj, sys.aud_policy$ pol
                  where obj.object_type='UNIFIED AUDIT POLICY' and
                  obj.object_id=pol.policy# and
                  pol.type=0 and
                  object_id not in (select policy# from sys.aud_object_opt$ )) loop
      -- unconditionally NOAUDIT the policy since it will not result in an error
      dbms_output.put_line('NOAUDIT POLICY '||ua_bin.object_name||';');
      dbms_output.put_line('DROP AUDIT POLICY '||ua_bin.object_name||';');
   end loop;
end;
/

spool off

set lines 80
set feedback on
set verify on
set heading on


 
