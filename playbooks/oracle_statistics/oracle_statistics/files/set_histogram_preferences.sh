#!/bin/bash
#
#  We use DBMS_STATS.SET_TABLE_PREFS to disable histograms on any DATE or
#  TIMESTAMP columns.  These tend to be monotonically increasing and are
#  therefore poor candidates for histograms as they will "bake in" a top
#  value for the date as around the current date, and thereby tend to 
#  greatly underestimate cardinality as the current date progresses far
#  beyond this, which can result in non-performant query plans.
#
#  We currently disable histograms on all DATE and TIMESTAMP columns; this
#  code may be extended in future if any are found to be required.
#
#  We currently allow Oracle to automatically determine the required
#  histograms for the other (non-date) columns.  Again this may be extended
#  in future to override if required.
#
SCHEMA=$1

. ~/.bash_profile

sqlplus -s /nolog <<EOSQL
connect / as sysdba

WHENEVER SQLERROR EXIT FAILURE
SET FEEDBACK OFF
SET SERVEROUT ON

DECLARE
  l_table_counter INTEGER := 0;
BEGIN
FOR x IN (
SELECT
    c.owner,
    c.table_name,
    'FOR ALL COLUMNS SIZE AUTO FOR COLUMNS SIZE 1 '||
       LISTAGG(c.column_name,',') WITHIN GROUP (ORDER BY c.column_name) histogram_preferences
FROM
    dba_tab_columns c
    INNER JOIN dba_tables t  -- Ensure it is a table rather than a view
    ON c.owner = t.owner
    AND c.table_name = t.table_name
WHERE
        c.owner = '${SCHEMA}'
    AND c.table_name NOT LIKE 'Z\_%' ESCAPE '\'
    AND c.table_name NOT LIKE 'Z_\_%' ESCAPE '\'
    AND c.table_name NOT LIKE '%$%'
    AND ( c.data_type = 'DATE'
          OR c.data_type LIKE 'TIMESTAMP%' )
GROUP BY
    c.owner,
    c.table_name
MINUS
SELECT p.owner,
       p.table_name,
       p.preference_value
FROM dba_tab_stat_prefs p
WHERE p.owner = '${SCHEMA}'
AND   p.preference_name = 'METHOD_OPT'
)
LOOP
   DBMS_STATS.set_table_prefs(
      ownname => x.owner,
      tabname => x.table_name,
      pname   => 'METHOD_OPT',
      pvalue => 'FOR ALL COLUMNS SIZE AUTO FOR COLUMNS SIZE 1 '||x.histogram_preferences
   );
END LOOP;
   DBMS_OUTPUT.put_line('Histogram preferences changed on '||l_table_counter||' tables.');
END;
/
EXIT
EOSQL