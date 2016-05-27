#!/bin/bash

set -e
set -o pipefail
set -u

DEST_FILENAME=$1

WORKING_DIR=/tmp/scanned_documents
OUTPUT_DIR=/tmp/scans
mkdir -p $WORKING_DIR
mkdir -p $OUTPUT_DIR

rm -f $WORKING_DIR/* > /dev/null 2>&1

LOG_FILE=$WORKING_DIR/scan.log

PAGE_NUMBER=1
READ_ANOTHER="Y"
IMAGES=""

RESULT_NAME=`date +"H_%M_%S"`_`basename "${DEST_FILENAME}"`

while test $READ_ANOTHER == "Y"
do
    echo "press return to start scan"
    read
    scanimage --format=tiff --mode Color --resolution 300 > $WORKING_DIR/page_${PAGE_NUMBER}.tiff

    IMAGES="${IMAGES} ${WORKING_DIR}/page_${PAGE_NUMBER}.tiff"
    PAGE_NUMBER=`echo "${PAGE_NUMBER}+1" | bc`
    echo "scan another page? (Y/[n])"
    read READ_ANOTHER;
done;

PAGE_NUMBER=1
SOURCE_PDFS=""

for IMAGE_NAME in $IMAGES; do 
    tesseract $IMAGE_NAME "${WORKING_DIR}/page_${PAGE_NUMBER}" -l eng pdf
    
    # hocr2pdf -i $IMAGE_NAME -o "${WORKING_DIR}/page_${PAGE_NUMBER}.pdf" < "${WORKING_DIR}/page_${PAGE_NUMBER}.hocr"
    
    SOURCE_PDFS="${SOURCE_PDFS} ${WORKING_DIR}/page_${PAGE_NUMBER}.pdf"
    PAGE_NUMBER=`echo "${PAGE_NUMBER}+1" | bc`
done

pdfjoin --fitpaper 'true' --no-tidy --outfile $OUTPUT_DIR/$RESULT_NAME ${SOURCE_PDFS} >> $LOG_FILE 2>&1

cp -i "${OUTPUT_DIR}/${RESULT_NAME}" "$DEST_FILENAME"
