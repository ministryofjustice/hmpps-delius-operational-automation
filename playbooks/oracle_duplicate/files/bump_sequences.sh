#!/bin/bash
#
#  In order to prevent test IDs overlapping with real IDs and causing potential ambiguity
#  in the audit trail, we bump all sequences to a sufficiently high value that no overlap
#  will practically occur within the expected lifetime of the application.
#

. ~/.bash_profile

sqlplus /nolog <<EOSQL
connect / as sysdba

DECLARE
   -- Ensure all new IDs are generated from 9,000,000,000 onwards as these IDs
   -- are sufficiently high as will never be reached in the live application.
   -- Note special handling for the SYSTEM_USER_ID_SEQ sequence which is
   -- capped at a lower maximum value than the other sequences.
   l_baseline_id CONSTANT INTEGER := 9000000000;
   l_dummy_id    INTEGER;
BEGIN
-- We ignore the OFFENDER_CRN_SEQ since test CRNs are generated by
-- changing the CRN_PREFIX in ND_PARAMETERS instead.
FOR x IN (SELECT sequence_owner,
                 sequence_name,
                 increment_by,
                 last_number,
                 cache_size,
                 CASE
                 WHEN sequence_name = 'SYSTEM_USER_ID_SEQ' THEN 9999000
                 ELSE l_baseline_id
                 END baseline_id
          FROM   dba_sequences
          WHERE  sequence_owner = 'DELIUS_APP_SCHEMA'
          AND    sequence_name != 'OFFENDER_CRN_SEQ'
          AND    sequence_name NOT LIKE 'Z_%')
LOOP
   -- We want to keep the existing MIN_VALUE the same as it exists in the source
   -- database, so we simply increment by a large enough value to
   -- reach the baseline value
   IF x.baseline_id-x.last_number > 0
   THEN
       EXECUTE IMMEDIATE 'ALTER SEQUENCE '||x.sequence_owner||'.'||x.sequence_name||
                             ' INCREMENT BY '||(x.baseline_id-x.last_number);
       -- Get next value to force incrementing (we avoid using cached values)
       EXECUTE IMMEDIATE 'ALTER SEQUENCE '||x.sequence_owner||'.'||x.sequence_name||' NOCACHE';
       EXECUTE IMMEDIATE 'SELECT '||x.sequence_owner||'.'||x.sequence_name||'.NEXTVAL FROM DUAL'
       INTO l_dummy_id;
       -- Now reset to the previous cache values and increment by
       EXECUTE IMMEDIATE 'ALTER SEQUENCE '||x.sequence_owner||'.'||x.sequence_name||' CACHE '||x.cache_size;
       EXECUTE IMMEDIATE 'ALTER SEQUENCE '||x.sequence_owner||'.'||x.sequence_name||
                         ' INCREMENT BY '||x.increment_by;
   END IF;
END LOOP;
END;
/
EXIT
EOSQL