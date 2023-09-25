#!/bin/bash
#
# Fetch metadata.xml files with information about how many chunks are required for each backup piece
#
# Parameters 1-3 are the respective parts of the object path in the S3 bucket
# Parameter 4 is the local directory to place the metadata files in
# Parameter 5 is how many days back in time we want to fetch metadata files 
# (Chunks are typically lost during backup creation, so we do not need to repeatedly validate older backups; 
#  therefore we avoid fetching all the metadata files, as this is slow and incurs AWS costs)
#

S3_URL=$1
DBID=$2
DATABASE_NAME=$3
OUTPUT_DIR=$4
NUM_OF_DAYS_BACK_TO_VALIDATE=$5

STARTDATE=$(date -d "${NUM_OF_DAYS_BACK_TO_VALIDATE} days ago" +%Y-%m-%d)
ENDDATE=$(date +%Y-%m-%d)

DAY_LOOP=${STARTDATE}

until [[ ${DAY_LOOP} > ${ENDDATE} ]];
do
   echo "${DAY_LOOP}"
   aws s3 cp s3://${S3_URL}/file_chunk/${DBID}/${DATABASE_NAME}/backuppiece/${DAY_LOOP} ${OUTPUT_DIR} --recursive --exclude "*" --include '*/metadata.xml' --only-show-errors
   DAY_LOOP=$(date -d "${DAY_LOOP} + 1 day"  +%Y-%m-%d)
done
