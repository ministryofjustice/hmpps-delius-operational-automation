#!/bin/bash
#
# check_grants.sh  — check which grants in a .sql file (in the $GRANTS environment variable) do NOT yet exist
#

. ~/.bash_profile

function exists_count {
  local priv="$1" obj="$2" grantee="$3"

  # We return 0 for an existing object with a missing privilege
  # We return NULL for a non-existing object (we skip those)
  sqlplus -s / as sysdba <<-SQL | tr -d '[:space:]'
    SET HEADING OFF FEEDBACK OFF PAGESIZE 0 VERIFY OFF
    WHENEVER SQLERROR EXIT FAILURE

	WITH object_exists AS (
	    SELECT
		COUNT(*) object_count
	    FROM
		dba_objects o
	    WHERE
		    ( o.owner
		      || '.'
		      || o.object_name ) = upper('$obj')
		AND object_type IN ( 'TABLE', 'FUNCTION', 'PROCEDURE', 'PACKAGE', 'PACKAGE BODY' )
	), privilege_exists AS (
	    SELECT
		COUNT(*) privilege_count
	    FROM
		dba_tab_privs t
	    WHERE
		    ( t.owner
		      || '.'
		      || t.table_name ) = upper('$obj')
		AND t.grantee = UPPER('$grantee')
		AND t.privilege = UPPER('$priv')
	)
	SELECT
	    CASE
		WHEN object_count > 0 THEN
		    privilege_count
		ELSE
		    NULL
	    END privilege_on_existing_object
	FROM
		 object_exists o
	    CROSS JOIN privilege_exists p;
    EXIT;
SQL
}

function add_privilege {
  local priv="$1" obj="$2" grantee="$3"

  sqlplus -s / as sysdba <<-SQL
    SET HEADING OFF FEEDBACK OFF PAGESIZE 0 VERIFY OFF
	WHENEVER SQLERROR EXIT FAILURE

    GRANT ${priv} ON $obj TO $grantee;
SQL
}

# process each GRANT line which should be supplied as standard input
echo "${GRANTS}" | grep -Ei '^\s*grant '| while read -r line; do
  # extract the clause between GRANT … ON
  priv_list=$(echo "$line" \
    | sed -E 's/GRANT[[:space:]]+(.+)[[:space:]]+ON.*/\1/Ip')
  # extract object owner.table
  obj=$(echo "$line" \
    | sed -n -E 's/.*ON[[:space:]]+([^[:space:]]+)[[:space:]]+TO.*/\1/Ip')
  # extract grantee
  grantee=$(echo "$line" \
    | sed -n -E 's/.*TO[[:space:]]+([^; ]+).*/\1/Ip')

  # split privileges on comma, check each
  IFS=',' read -ra PRS <<< "$priv_list"
  for p in "${PRS[@]}"; do
    p_trim=$(echo "$p" | xargs)    # trim whitespace
    cnt=$(exists_count "$p_trim" "$obj" "$grantee")
    if [[ "$cnt" == "0" ]]; then
      echo "ADDING: $p_trim ON $obj TO $grantee"
      add_privilege "$p_trim" "$obj" "$grantee"
    elif [[ -z "$cnt" ]]; then
	    echo "OBJECT DOES NOT EXIST: $obj"
    else
	    echo "PRIVILEGE EXISTS: $p_trim ON $obj TO $grantee"
    fi
  done
done