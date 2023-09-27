#!/bin/bash
#
# Count the number of chunks actually present for each backup piece 
#
# Parameters 1-3 are the respective parts of the object path in the S3 bucket
# Parameter 4 is the local directory to place the metadata files in
# Parameter 5 is how many days back in time we want to fetch metadata files 
# (Chunks are typically lost during backup creation, so we do not need to repeatedly validate older backups; 
#  therefore we avoid counting all the chunks, as this is slow and incurs AWS costs)
#

. ~/.bash_profile

S3_URL=$1
DBID=$2
DATABASE_NAME=$3
OUTPUT_DIR=$4
NUM_OF_DAYS_BACK_TO_VALIDATE=$5

# Initialize the Output File
>${OUTPUT_DIR}/actual_chunks.txt

STARTDATE=$(date -d "${NUM_OF_DAYS_BACK_TO_VALIDATE} days ago" +%Y-%m-%d)
ENDDATE=$(date +%Y-%m-%d)

DAY_LOOP=${STARTDATE}

until [[ ${DAY_LOOP} > ${ENDDATE} ]];
do
   echo "${DAY_LOOP}"
   aws s3 ls s3://${S3_URL}/file_chunk/${DBID}/${DATABASE_NAME}/backuppiece/${DAY_LOOP} --recursive \
          | egrep "/[[:digit:]]{10}$" \
          | awk '!/metadata.xml/{print $NF}' \
          | rev  | cut -d/ -f2- | rev \
          | cut -d/ -f6- |  rev \
          | cut -d/ -f2- | rev \
          | sort | uniq -c | awk '{print $2,$1}' >> ${OUTPUT_DIR}/actual_chunks.txt 
   DAY_LOOP=$(date -d "${DAY_LOOP} + 1 day"  +%Y-%m-%d)
done
