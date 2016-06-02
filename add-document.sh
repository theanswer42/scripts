#!/bin/bash

set -e
set -o pipefail
set -u

# copy a given document or a scanned document to the right place (documents/<year>/<month>)
# usage:
# add-document.sh -s <scan-name>
# 
# OR
# add-document.sh -i <filename>
# use -y <year> -m <month> to not use today as date.
# month is mm
# year is yyyy
#
# if -s is given, it will override -i
# 

DOCUMENTS_DIR=/volumes/alexandria/documents

SCANNER="scan_document.sh"

SCAN=0
YEAR=0
MONTH=0

while getopts ":s:y:m:i:" opt; do
    case $opt in
	i)
	    INPUT_FILENAME="$OPTARG"
	    ;;
	s)
	    SCAN_NAME="$OPTARG"
	    SCAN=1
	    ;;
	y)
	    YEAR=$OPTARG
	    ;;
	m)
	    MONTH=$OPTARG
	    ;;
	\?)
	    echo "Invalid option: -$OPTARG" >&2
	    exit 1
	    ;;
	:)
	    echo "Option -$OPTARG requires an argument." >&2
	    exit 1
	    ;;
    esac
done

if test $YEAR == "0" || test $MONTH == "0"; then
    YEAR=`date +"%Y"`
    MONTH=`date +"%m"`
fi

if ! test -d "$DOCUMENTS_DIR"; then
    echo "documents dir does not exist!" >&2
    exit 1
fi

DEST_DIR="${DOCUMENTS_DIR}/${YEAR}/${MONTH}"

mkdir -p "$DEST_DIR"

if test $SCAN == "1"; then
    SCAN_NAME=`basename "$SCAN_NAME" .pdf`

    $SCANNER "${DEST_DIR}/${SCAN_NAME}.pdf"
    echo "scanned document to ${DEST_DIR}/${SCAN_NAME}.pdf"
else
    if ! test -f "$INPUT_FILENAME"; then
	echo "input file does not exist or not given! use -i <input-filename>" >&2
	exit 1
    fi
    echo -n "copying $INPUT_FILENAME to $DEST_DIR..."
    cp -i "$INPUT_FILENAME" "$DEST_DIR"
    echo "done"
fi

