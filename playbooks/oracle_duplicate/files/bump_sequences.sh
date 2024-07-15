#!/bin/bash
#
#  In order to prevent test IDs overlapping with real IDs and causing potential ambiguity
#  in the audit trail, we bump all sequences to a sufficiently high value that no overlap
#  will practically occur within the expected lifetime of the application.
#

DECLARE
   -- Ensure all new IDs are generated from 9,000,000,000 onwards as these IDs
   -- are sufficiently high as will never be reached in the live application.
   l_baseline_id CONSTANT INTEGER := 9000000000;
   l_dummy_id    INTEGER;
BEGIN
FOR x IN (SELECT sequence_owner,
                 sequence_name,
                 increment_by,
                 last_number
          FROM   dba_sequences
          WHERE  sequence_owner = 'DELIUS_APP_SCHEMA'
          AND    sequence_name NOT LIKE 'Z_%')
LOOP
   -- We want to keep the existing MIN_VALUE the same as it exists in the source
   -- database, so we simply increment by a large enough value to
   -- reach the baseline value
   IF l_baseline_id-x.last_number > 0
   THEN
       EXECUTE IMMEDIATE 'ALTER SEQUENCE '||x.sequence_owner||'.'||x.sequence_name||
                         ' INCREMENT BY '||(l_baseline_id-x.last_number);
       -- Get next value to force incrementing
       EXECUTE IMMEDIATE 'SELECT '||x.sequence_owner||'.'||x.sequence_name||'.NEXTVAL FROM DUAL'
       INTO l_dummy_id;
       -- Now reset to the previous increment by
       EXECUTE IMMEDIATE 'ALTER SEQUENCE '||x.sequence_owner||'.'||x.sequence_name||
                         ' INCREMENT BY '||x.increment_by;
   END IF;
END LOOP;
END;
/

   
   
