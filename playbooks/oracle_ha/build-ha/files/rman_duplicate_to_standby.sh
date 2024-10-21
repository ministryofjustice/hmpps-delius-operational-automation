#!/bin/bash

PATH=$PATH:/usr/sbin:/usr/local/bin
THISSCRIPT=`basename $0`
RMANCMDFILE=/tmp/rmanduplicatestandby.cmd
RMANLOGFILE=/tmp/rmanduplicatestandby.log
RMANARCCLRLOG=/tmp/rmanarchiveclear.log
RMANSCRIPTLOG=/tmp/rmanscript.log
>>${RMANSCRIPTLOG}
CPU_COUNT=$((`grep processor /proc/cpuinfo | wc -l`/2))

info () {
  T=`date +"%D %T"`
    echo -e "INFO : $THISSCRIPT : $T : $1"
    echo -e "INFO : $THISSCRIPT : $T : $1" >> ${RMANSCRIPTLOG}
}

error () {
  T=`date +"%D %T"`
  echo -e "ERROR : $THISSCRIPT : $T : $1"
  echo -e "ERROR : $THISSCRIPT : $T : $1" >> ${RMANSCRIPTLOG}
  exit 1
  }

 usage () {
   echo ""
   echo "Usage:"
   echo ""
   echo "  $THISSCRIPT -t <primary db> -s <standby db> -p <sys password> -i < init pfile> [ -p <ssm parameter> ] [ -c <catalog TNS string> ] [-f] [-b]"
   echo ""
   echo "  Parameterized Options:"
   echo ""
   echo "  -t primary db              = primary database name"
   echo "  -s standby db              = standby database name"
   echo "  -p sys password            = database sys password"
   echo "  -i init pfile              = parameter initialization file"
   echo "  -p ssm parameter           = ssm parameter name to be updated"
   echo "  -c catalog TNS string      = connection string to RMAN catalog (only required if duplicating from backup)"
   echo ""
   echo " Non-Parameterized Options:"
   echo ""
   echo "  -f will force a database duplication regardless of dataguard status"
   echo "  -b will force a database duplication using a backup of the primary (default is to use active database duplication)"
   echo "  -n no SBT type channels (used for Active Duplication or Disk-Based backups outside of AWS)"
   echo "  -r fetch redo logs from primary since RESETLOGS (used if this standby is a DMS source endpoint and needs all redo"
   echo "     generated since database creation, not just since standby creation)"
   echo ""
   exit 1
}

set_ora_env () {
  export ORAENV_ASK=NO
  export ORACLE_SID=$1
  . oraenv
  unset SQLPATH
  unset TWO_TASK
  unset LD_LIBRARY_PATH
  export NLS_DATE_FORMAT=YYMMDDHH24MI
}

startup_mount_standby() {
  sqlplus -s / as sysdba << EOF
  startup nomount pfile='${PARAMFILE}'
EOF
}



lookup_rman_catalog_password() {

  info "Looking up rman catalog password in aws secret"

  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/EC2OracleEnterpriseManagementSecretsRole"
  CREDS=$(aws sts assume-role --role-arn "${ROLE_ARN}" --role-session-name "catalog-ansible"  --output text --query "Credentials.[AccessKeyId,SecretAccessKey,SessionToken]")
  export AWS_ACCESS_KEY_ID=$(echo "${CREDS}" | tail -1 | cut -f1)
  export AWS_SECRET_ACCESS_KEY=$(echo "${CREDS}" | tail -1 | cut -f2)
  export AWS_SESSION_TOKEN=$(echo "${CREDS}" | tail -1 | cut -f3)
  SECRET_ARN="arn:aws:secretsmanager:eu-west-2:${SECRET_ACCOUNT_ID}:secret:/oracle/database/${CATALOG}/shared-passwords"
  RMANPASS=$(aws secretsmanager get-secret-value --secret-id "${SECRET_ARN}" --query SecretString --output text | jq -r .rcvcatowner)
  [ -z ${RMANPASS} ] && error "Password for RMAN catalog in aws secret does not exist"
  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

}


lookup_db_passwords() {

 info "Looking up sys and asmsnmp passwords from aws secret"

  INSTANCE_ID=$(wget -q -O - http://169.254.169.254/latest/meta-data/instance-id)
  APPLICATION=$(aws ec2 describe-tags --filters "Name=resource-id,Values=${INSTANCE_ID}" "Name=key,Values=application" --query 'Tags[0].Value' --output text)
  if [ "$APPLICATION" = "delius" ]
  then
    SECRET_ID="${ENVIRONMENT_NAME}-oracle-db-dba-passwords"
  elif [ "$APPLICATION" = "delius-mis" ]
  then
    DATABASE_TYPE=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$INSTANCE_ID" "Name=key,Values=database" --query 'Tags[0].Value' --output text | cut -d'_' -f1)
    SECRET_ID="${ENVIRONMENT_NAME}-oracle-${DATABASE_TYPE}-db-dba-passwords"
  fi
  SYSPASS=$(aws secretsmanager get-secret-value --secret-id ${SECRET_ID} --query SecretString --output text| jq -r .sys)
  ASMSNMPPASS=$(aws secretsmanager get-secret-value --secret-id ${SECRET_ID} --query SecretString --output text| jq -r .asmsnmp)
  [ -z ${SYSPASS} ] && error "Password for sys in aws secret ${SECRET_ID} does not exist"
  [ -z ${ASMSNMPPASS} ] && error "Password for asmsnmp in aws secret ${SECRET_ID} does not exist"
}

get_primary_dbid () {
  info "Getting DBID of Primary Database"
  DBID=$(
  sqlplus -s sys/${SYSPASS}@${PRIMARYDB} as sysdba << EOF
      SET LINES 1000
      SET PAGES 0
      SET FEEDBACK OFF
      SET HEADING OFF
      WHENEVER SQLERROR EXIT FAILURE
      SELECT dbid
      FROM   v\$database;
      EXIT
EOF
      )
  [ $? -ne 0 ] && error "Primary database DBID is ${DBID}"
}

get_resetlogs_scn () {
  info "Getting SCN of RESETLOGS"
  RESETLOGS_SCN=$(
  sqlplus -s sys/${SYSPASS}@${PRIMARYDB} as sysdba << EOF
      SET LINES 1000
      SET PAGES 0
      SET FEEDBACK OFF
      SET HEADING OFF
      COL resetlogs_change# FORMAT 99999999990
      WHENEVER SQLERROR EXIT FAILURE
      SELECT resetlogs_change#
      FROM   v\$database;
      EXIT
EOF
      )
  [ $? -ne 0 ] && error "RESETLOGS SCN is ${RESETLOGS_SCN}"
}

get_source_db_rman_details () {

  X=`sqlplus -s rman19c/${RMANPASS}@"${CATALOG_TNS_STRING}" <<EOF
      whenever sqlerror exit failure
      set feedback off heading off verify off echo off

      with completion_times as
        (select max(d.next_change#)                           arch_scn
          from rc_database a,
               bs b,
               rc_database_incarnation c,
               rc_backup_archivelog_details d
          where a.name = '${PRIMARYDB}'
          and a.db_key=b.db_key
          and a.db_key=c.db_key
          and a.dbinc_key = c.dbinc_key
          and b.bck_type is not null
          and b.bs_key not in (select bs_key
                              from rc_backup_controlfile
                              where autobackup_date is not null
                              or autobackup_sequence is not null)
          and b.bs_key not in (select bs_key
                              from  rc_backup_spfile)
          and b.db_key=d.db_key(+)
          and a.dbid = ${DBID}
          and d.btype(+) = 'BACKUPSET'
          and b.bs_key=d.btype_key(+)
          group by a.dbid,b.bck_type)
      select  'SCN='||to_char(max(arch_scn))
      from completion_times;
EOF
`
  eval $X
  [ $? -ne 0 ] && error "Getting $PRIMARYDB rman details"
  info "${PRIMARYDB} dbid = ${DBID}"
  info "Restore SCN  = ${SCN}"
}


rman_duplicate_to_standby () {

  echo "run"                                                                > $RMANCMDFILE
  echo "{"                                                                  >> $RMANCMDFILE
  for (( i=1; i<=${CPU_COUNT}; i++ ))
  do
    if [[ "${USE_BACKUP}" != "TRUE" ]]
    then
         # Allocate Disk Channel if using Active Duplication
         echo "  allocate channel ch${i} device type disk;"                      >> $RMANCMDFILE
    else
       # If using Backup based duplicate then must use Auxiliary channels instead of normal channels
       if [[ "${NO_SBT_CHANNELS}" == "TRUE" ]]
       then
         # Allocate Disk Channel if using Active Duplication or Outside of AWS (Disk backups)
         echo "  allocate auxiliary channel ch${i} device type disk;"                      >> $RMANCMDFILE
       else
         # Allocate SBT Channel if using a Backup inside AWS
         echo "  allocate auxiliary channel c${i} device type sbt parms='SBT_LIBRARY=${ORACLE_HOME}/lib/libosbws.so, ENV=(OSB_WS_PFILE=${ORACLE_HOME}/dbs/osbws.ora)';" >>$RMANCMDFILE
       fi
    fi
  done
  for (( i=1; i<=${CPU_COUNT}; i++ ))
  do
    echo "  allocate auxiliary channel drch${i} device type disk;"          >> $RMANCMDFILE
  done

  get_primary_dbid

  if [[ "${USE_BACKUP}" != "TRUE" ]]
  then
      # Unless we have used the -b flag then we use Duplicate for Active Database
      # Note than in AWS the use of Active Database Duplication may incur Regional
      # Data Transfer charges.
      echo "  duplicate target database"                                        >> $RMANCMDFILE
      echo "   for standby"                                                     >> $RMANCMDFILE
      echo "   from active database"                                            >> $RMANCMDFILE
      echo "    dorecover"                                                      >> $RMANCMDFILE
  else
      echo "  duplicate database ${primarydb} dbid ${DBID}"                     >> $RMANCMDFILE
      echo "   for standby"                                                     >> $RMANCMDFILE
  fi

  echo "    spfile parameter_value_convert ('${primarydb}','${standbydb}')" >> $RMANCMDFILE
  echo "          set db_unique_name='${standbydb}'"                        >> $RMANCMDFILE
  echo "          set fal_server='${primarydb}'"                            >> $RMANCMDFILE
  echo "          set fal_client='${standbydb}'"                            >> $RMANCMDFILE
  echo "          set audit_file_dest='/u01/app/oracle/admin/${standbydb}/adump'" >> $RMANCMDFILE
  echo "          set log_archive_dest_1='location=use_db_recovery_file_dest valid_for=(all_logfiles, all_roles) db_unique_name=${standbydb}'" >> $RMANCMDFILE
  echo "          set log_archive_dest_2=''"   >> $RMANCMDFILE
  echo "          set log_archive_dest_3=''"   >> $RMANCMDFILE
  echo "          set dg_broker_config_file1='+DATA/${standbydb}/dg_broker1.dat'" >> $RMANCMDFILE
  echo "          set dg_broker_config_file2='+FLASH/${standbydb}/dg_broker2.dat'" >> $RMANCMDFILE
  echo "          set dg_broker_start='true'" >> $RMANCMDFILE
  echo "          set standby_file_management='auto'" >> $RMANCMDFILE

  if [[ "${USE_BACKUP}" == "TRUE" ]]
  then
      # If we are restoring from a backup, we must specify an SCN which will make the database consistent
      # since we cannot enable flashbacking logging on an inconsistent database
      lookup_rman_catalog_password
      get_source_db_rman_details
      echo "  until scn ${SCN}" >> $RMANCMDFILE  
  fi

  echo "  nofilenamecheck;" >> $RMANCMDFILE
  echo "}" >> $RMANCMDFILE

  if [[ "${USE_BACKUP}" != "TRUE" ]]
  then
     rman target sys/${SYSPASS}@${PRIMARYDB} auxiliary sys/${SYSPASS}@${STANDBYDB} cmdfile $RMANCMDFILE log $RMANLOGFILE << EOF
EOF
  else
     # If we are duplicating from a backup then we need to connect to the RMAN catalog to get the backup manifest
     if [[ "${NO_SBT_CHANNELS}" == "TRUE" ]]
     then
        # If the backup is disk based then we must NOT connect to the target DB (an error is thrown if connecting)
        rman auxiliary sys/${SYSPASS}@${STANDBYDB} catalog rman19c/${RMANPASS}@"${CATALOG_TNS_STRING}" cmdfile $RMANCMDFILE log $RMANLOGFILE << EOF
EOF
     else
        # If the backup is SBT based then we must connect to the target DB.
        # (This should not be necessary according to the Oracle documentation but it cannot find the SPFILE when tried without it)
        rman auxiliary sys/${SYSPASS}@${STANDBYDB} catalog rman19c/${RMANPASS}@"${CATALOG_TNS_STRING}" target sys/${SYSPASS}@${PRIMARYDB} cmdfile $RMANCMDFILE log $RMANLOGFILE << EOF
EOF
     fi
  fi

  info "Checking for errors"
  grep -i "ERROR MESSAGE STACK" $RMANLOGFILE >/dev/null 2>&1
  [ $? -eq 0 ] && error "Rman reported errors"
  info "Rman duplcate completed successfully"
}

perform_recovery () {
  info "Check standby recovery"
  sqlplus -s / as sysdba << EOF
    alter database flashback on;
    alter database recover managed standby database disconnect;
    exit;
EOF
  [ $? -ne 0 ] && error "Recovering the standby" || info "Standby ${STANDBYDB} now recovering"
}

create_asm_spfile () {
  info "Add spfile to ASM"
  # Within 18c the SPFILE will have been duplicated to the DB_UNKNOWN directory within ASM, and an
  # alias created for it (instead of to the file system as would have happened with 11g).
  # To move the SPFILE to the intended destination it is necessary to bounce the instance using the temporary pfile.   
  # This will also remove the DB_UNKNOWN directory and aliases.
  sqlplus -s / as sysdba <<EOF
  create pfile='${ORACLE_HOME}/dbs/tmp.ora' from spfile;
  shutdown immediate;
  -- Database must be mounted when creating new SPFILE otherwise it will end up back in DB_UNKNOWN
  -- The restart is really only required for 18c but are harmless to do for 11g also.
  startup mount pfile='${ORACLE_HOME}/dbs/tmp.ora';
  -- Recreating the SPFILE will automatically remove the DB_UNKNOWN directory from ASM and aliases.
  create spfile='+DATA/${STANDBYDB}/spfile${STANDBYDB}.ora' from pfile='${ORACLE_HOME}/dbs/tmp.ora';
  shutdown immediate;
  startup mount;
EOF
  [ $? -ne 0 ] && error "Creating spfile in ASM"
  info "Create new pfile and remove spfile"
  echo "SPFILE='+DATA/${STANDBYDB}/spfile${STANDBYDB}.ora'" > ${ORACLE_HOME}/dbs/init${STANDBYDB}.ora
  rm -f ${ORACLE_HOME}/dbs/spfile${STANDBYDB}.ora ${ORACLE_HOME}/dbs/tmp.ora
}

add_to_crs () {
  info "Add ${standbydb} database resource to CRS if not already"
  sqlplus -s / as sysdba <<EOF
   shutdown abort
   exit
EOF
  # Allow slight pause for CRS to detect database down as shutdown using sqlplus
  sleep 30
  srvctl status database -d ${STANDBYDB} > /dev/null
  if [ $? -ne 0 ]
  then
    srvctl add database -d ${STANDBYDB} -o ${ORACLE_HOME} -p +DATA/${STANDBYDB}/spfile${STANDBYDB}.ora -r PHYSICAL_STANDBY -s MOUNT -t IMMEDIATE -i ${STANDBYDB} -n ${PRIMARYDB} -y AUTOMATIC -a "DATA,FLASH"
    [ $? -ne 0 ] && error "Adding ${STANDBYDB} to CRS" || info "Added ${STANDBYDB} to CRS"
  fi
  srvctl start database -d ${STANDBYDB} -o MOUNT
  [ $? -ne 0 ] && error "Starting ${STANDBYDB} CRS resource" || info "Started ${STANDBYDB} with CRS resource"

 }

configure_rman () {
  rman target / <<EOF
    CONFIGURE ARCHIVELOG DELETION POLICY TO APPLIED ON STANDBY;
EOF
}

# At the time when the primary database was backed up (assuming non-Active Duplication) it may not have had
# Standby Logfiles (e.g. if it had just been refreshed).   Therefore these would not automatically be created on the Standby.
# We call this function to ensure that they are always in place.
# (Slight variation on this code from pimary as cannot use subquery factoring on standby)
create_standby_logfiles () {
  info "Create standby log files"
  sqlplus -s / as sysdba << EOF
  set head off pages 1000 feed off
  declare
    cursor c1 is
      select 'alter database add standby logfile thread 1 group '||rn||' size '||mb cmd
          from ( select cnt, mg, mb, rownum as rn
                 from (select count(*) as cnt, max(group#) as mg, max(bytes) as mb from v\$log)
                 connect by level <= ((mg)+(cnt)+1))
      where rn > mg
      and rn not in (select group# from v\$standby_log);

      sql_stmt varchar2(400);

  begin
    for r1 in c1
    loop
      sql_stmt := r1.cmd;
      execute immediate sql_stmt;
    end loop;
  end;
  /
EOF
  [ $? -ne 0 ] && error "Creating standby log files" || info "Created standby log files"
}


remove_orphaned_archive () {
  info "Remove orphaned archived redo logs"

  V_PARAMETER=v\$parameter
  V_INSTANCE=v\$instance

  X=`sqlplus -s / as sysdba <<EOF
      set feedback off heading off echo off verify off
      SELECT     'export ARCHIVE_DEST='||p.value||'/'|| i.instance_name||'/archivelog'
      FROM       $V_PARAMETER   p
      CROSS JOIN $V_INSTANCE   i
      WHERE      p.name = 'db_recovery_file_dest';     
EOF
  `
  eval $X
  [ $? -ne 0 ] && error "Getting archive destination" || info "Got archive destination"

  # As soon as we catalog the recovery destination, the orphaned redo logs
  # will be automatically removed from ASM by Oracle.  So we simply need to
  # crosscheck and delete the associated records.
  rman target / log $RMANARCCLRLOG <<EOF
      CATALOG START WITH '$ARCHIVE_DEST';
      CROSSCHECK ARCHIVELOG ALL;
      DELETE NOPROMPT EXPIRED ARCHIVELOG ALL;
      exit
EOF
  [ $? -ne 0 ] && error "Removing orphaned archivelogs" || info "Removed orphaned archivelogs"
}

remove_asm_directories () {
  sleep 10
  info "Shutdown instance ${STANDBYDB}"
  sqlplus / as sysdba << EOF
  shutdown abort;
EOF
  [ $? -ne 0 ] && error "Shutting down ${STANDBYDB}"

  sleep 10
  set_ora_env +ASM

  for VG in DATA FLASH
  do
    info "Remove directory ${STANDBYDB} in ${VG} volume group"
    asmcmd ls +${VG}/${STANDBYDB} > /dev/null 2>&1
    if [ $? -eq 0 ]
    then
      asmcmd rm -rf +${VG}/${STANDBYDB}
      [ $? -ne 0 ] && error "Removing directory ${STANDBYDB} in ${VG}"
    else
      info "No ${STANDBYDB} directory in ${VG} to delete"
    fi
  done
  # From 18c we must have the second level ASM directories in place before restoring SPFILE
  # as it will now fail rather than defaulting to $ORACLE_HOME/dbs as it did previously.
  for VG in DATA FLASH
  do
    info "Create directory ${STANDBYDB} in ${VG} volume group"
    asmcmd mkdir +${VG}/${STANDBYDB}
  done

  sleep 10
}

initialise_password_file() {
   # Ensure the password file is initially created on the file system rather than ASM.
   # This is due to a change in behaviour in 19c where the password file is automatically copied
   # from the primary database during active duplication; this happens immediately after the database
   # is mounted - there appears to be a short interval where the ASM diskgroups are
   # reconnected which leads to writing of the copied password file to randomly fail on
   # some occassions with a diskgroup not mounted error.
   # (this is speculation - a definitive bug record for this has not been found)
   # To avoid the problem we start with the password file on the file system and only
   # move it onto ASM at the end of the duplication.
   set_ora_env ${STANDBYDB}
   info "Initialising password file location to ${ORACLE_HOME}/dbs/orapw${STANDBYDB}"
   srvctl modify database -d ${STANDBYDB} -pwfile ${ORACLE_HOME}/dbs/orapw${STANDBYDB}
   info "Creating seed password file (will be replaced by active duplicate)"
   rm -f ${ORACLE_HOME}/dbs/orapw${STANDBYDB}
   orapwd file=${ORACLE_HOME}/dbs/orapw${STANDBYDB} password=${SYSPASS}
}


remove_standby_parameter_files () {
  set_ora_env ${STANDBYDB}
  ls ${ORACLE_HOME}/dbs/*${STANDBYDB}* | egrep -v "${PARAMFILE}|orapw${STANDBYDB}" | xargs -r rm
  [ $? -ne 0 ] && error "Removing standby parameter files"
}

get_asm_diskgroup_status () {
  SID=$1
  ROLE=$2
  set_ora_env $SID
  ASM_DISKGROUP_STATUS=$(sqlplus -s / as ${ROLE}<<EOSQL
  SET HEAD OFF
  SET PAGES 0
  select listagg(name||'==>'||state,'; ') from v\$asm_diskgroup;
EOSQL
  )
  info "Diskgroup status (from $SID): ${ASM_DISKGROUP_STATUS}"  
}

report_asm_diskgroup_status () {
  get_asm_diskgroup_status +ASM sysasm
  get_asm_diskgroup_status ${STANDBYDB} sysdba
}

move_password_file_to_asm () {
set_ora_env +ASM
CURRENT_PASSWORD_FILE=$(srvctl config database -d ${STANDBYDB} | awk '/^Password file:/{print $3}')
info "Moving password file from ${CURRENT_PASSWORD_FILE} to DATA disk group on ASM"
asmcmd <<EOASMCMD
pwcopy ${CURRENT_PASSWORD_FILE} +DATA/${STANDBYDB}/orapw${STANDBYDB} 
EOASMCMD
rm -f ${CURRENT_PASSWORD_FILE}
set_ora_env ${STANDBYDB}
info "Updating password file location"
srvctl modify database -d ${STANDBYDB} -pwfile "+DATA/${STANDBYDB}/orapw${STANDBYDB}"
}

fetch_redo_logs_since_resetlogs() {
  get_resetlogs_scn
  info "Fetching all redo logs since SCN ${RESETLOGS_SCN} from the primary"
  rman log /tmp/fetch_all_redo_logs_since_resetlogs.log <<EORMAN
connect target sys/${SYSPASS}@${PRIMARYDB}
connect auxiliary sys/${SYSPASS}@${STANDBYDB}
run {
   backup as copy reuse archivelog from scn ${RESETLOGS_SCN} auxiliary format '+FLASH';
}
exit
EORMAN
  info "Registering all fetched redo logs"
  rman log /tmp/registering_fetched_redologs.log <<EORMAN
connect target /
catalog start with '+FLASH' noprompt;
exit
EORMAN
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
info "Start"

# ------------------------------------------------------------------------------
# Check that we are running as the correct user (oracle)
# ------------------------------------------------------------------------------
info "Validating user"
THISUSER=`id | cut -d\( -f2 | cut -d\) -f1`
[ "$THISUSER" != "oracle" ] && error "Must be oracle to run this script"
info "User ok"

# ------------------------------------------------------------------------------
# Check that we have been given all the required arguments
# ------------------------------------------------------------------------------
info "Retrieving arguments"
[ -z "$1" ] && usage

TARGETDB=UNSPECIFIED
SSM_PARAMETER=UNSPECIFIED

while getopts "t:s:i:p:c:fbnr" opt
do
  case $opt in
    t) PRIMARYDB=$OPTARG ;;
    s) STANDBYDB=$OPTARG ;;
    i) PARAMFILE=$OPTARG ;;
    f) FORCERESTORE=TRUE ;;
    p) SSM_PARAMETER=$OPTARG ;;
    c) CATALOG_TNS_STRING=$OPTARG ;;
    b) USE_BACKUP=TRUE ;;
    n) NO_SBT_CHANNELS=TRUE ;;
    r) COPY_ALL_REDO_SINCE_RESETLOGS=TRUE ;;
    *) usage ;;
  esac
done

if [[ -z ${ENVIRONMENT_NAME} ]]
then
   error "The ENVIRONMENT_NAME environment variable must be set"
fi
info "Primary Database = ${PRIMARYDB}"
info "Standby Database = ${STANDBYDB}"
info "SSM parameter    = $SSM_PARAMETER"
if [[ "${FORCERESTORE}" == "TRUE" ]];
then
   info "Force Restore selected"
fi
if [[ "${USE_BACKUP}" == "TRUE" ]]
then  
   if [[ -z ${CATALOG_TNS_STRING} ]]
   then   
      error "RMAN catalog connection required if using backup"
   else  
      info "Using Restore from Backup of primary"
   fi
else
   info "Using Active Database Duplication from primary"
fi
if [[ "${COPY_ALL_REDO_SINCE_RESETLOGS}" == "TRUE" ]]
then
  info "Flag set to copy all redo logs since RESETLOGS on completion of duplicate"
fi

primarydb=`echo "${PRIMARYDB}" | tr '[:upper:]' '[:lower:]'`
standbydb=`echo "${STANDBYDB}" | tr '[:upper:]' '[:lower:]'`

# ------------------------------------------------------------------------------
# Check parameters
# ------------------------------------------------------------------------------
[ -z "$1" ] && usage

# Create audit directory
mkdir -p /u01/app/oracle/admin/${standbydb}/adump
[ $? -ne 0 ] && error "Creating the audit directory"

# Check if standby database configured in dgbroker (but only if we are not going to force a build anyway otherwise it is a waste of time)
set_ora_env ${STANDBYDB}

if [[ "${FORCERESTORE}" != "TRUE" ]]
then

    dgmgrl /  "show configuration" | grep "Physical standby database"  | grep "${standbydb}" > /dev/null
    PHYSICAL_STANDBY_CONFIG=$?

    if [[ ${PHYSICAL_STANDBY_CONFIG} -eq 0 ]];
    then
      info "${standbydb} already configured in dgbroker"
    else
      info "${standbydb} not configured in dgbroker"
    fi

    # Check if ORA-16700 error code associated with standby (requires rebuild)
    dgmgrl /  "show database ${standbydb}" | grep "ORA-16700: the standby database has diverged from the primary database" > /dev/null
    PHYSICAL_STANDBY_DIVERGENCE=$?

    if [[ ${PHYSICAL_STANDBY_DIVERGENCE} -eq 0 ]];
    then
      info "${standbydb} has diverged from the primary database"
    fi

    # Check if ORA-16766 error code associated with standby (requires rebuild)
    dgmgrl /  "show database ${standbydb}" | grep "ORA-16766: Redo Apply is stopped" > /dev/null
    REDO_APPLY_STOPPED=$?

    if [[ ${REDO_APPLY_STOPPED} -eq 0 ]];
    then
      info "${standbydb} redo apply has stopped when it should have been running"
    fi

    # Check if ORA-16603 error code associated with standby (configuration ID mismatch)
    dgmgrl /  "show database ${standbydb}" | grep "ORA-16603: Data Guard broker detected a mismatch in configuration ID" > /dev/null
    DG_CONFIGURATION_MISMATCH=$?

    if [[ ${DG_CONFIGURATION_MISMATCH} -eq 0 ]];
    then
      info "${standbydb} has a mismatched dataguard configuration"
    fi

    if [[ ${PHYSICAL_STANDBY_CONFIG} -eq 0 && ${PHYSICAL_STANDBY_DIVERGENCE} -ge 1 && ${REDO_APPLY_STOPPED} -ge 1 && ${DG_CONFIGURATION_MISMATCH} -ge 1  ]];
    then
      info "${standbydb} already configured in dgbroker, can assume no duplicate required"
    else
      info "forcing rebuild to clear error"
      FORCERESTORE=TRUE
    fi
fi

if [[ "${FORCERESTORE}" == "TRUE" ]]
then

  # Shutdown standby instance and remove standby database from DATA and FLASH asm diskgroups
  remove_asm_directories

  # As of 19c we do not need to copy the password file from primary as this happens
  # automatically; however we initialise the location of the password file on disk
  # to avoid race condition with disk group mounting
  lookup_db_passwords
  initialise_password_file

  # Remove unneccesary standby parameter files
  remove_standby_parameter_files

  # Startup no mount standby instance for rman duplicate
  startup_mount_standby

  # Report ASM diskgroup status (debug ORA-15001 issue)
  report_asm_diskgroup_status

  # Perform rman duplicate
  rman_duplicate_to_standby

  # Add to CRS
  create_asm_spfile
  add_to_crs

  # Ensure Standby Log files exist if restoring from a backup
  if [[ "${USE_BACKUP}" == "TRUE" ]]
  then  
     create_standby_logfiles
  fi

  # Perform recovery
  perform_recovery
  move_password_file_to_asm

  # Configure RMAN
  configure_rman

  # Remove orphaned archivelogs left by previous incarnation
  remove_orphaned_archive

  if [[ "${COPY_ALL_REDO_SINCE_RESETLOGS}" == "TRUE" ]]
  then
    fetch_redo_logs_since_resetlogs
  fi
fi

info "End"

# Exit with success status if no error found
exit 0
