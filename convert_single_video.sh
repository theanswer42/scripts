#!/bin/sh

usage()
{
    cat <<EOF
    usage: $0 -f filename
    
    Convert a single video into a format suitable for html5 video streaming
    
    Options:
    -h   Show this message
    -f   directory to import
EOF
}

check_error()
{
    STATUS=$1
    ERROR_MESSAGE=$2
    if [ $STATUS != 0 ]
    then
	echo $ERROR_MESSAGE
	exit 1
    fi
}

while getopts "hf:" OPTION
do
    case $OPTION in 
	h) 
	    usage
	    exit 0
	    ;;
	f)
	    SOURCE_FILE=${OPTARG}
	    ;;
    esac
done

if [ ! -f "${SOURCE_FILE}" ]
then
    echo "File ${SOURCE_FILE} does not exist"
    usage
    exit
fi

EXTENSION=`echo "${SOURCE_FILE##*.}"`

#  .avi, .divx, .m4v, .mkv, .mp4, .ogm

CONVERSION_REQUIRED=1
VALID_VIDEO_FORMAT=0

case "$EXTENSION" in
    mp4)
	CONVERSION_REQUIRED=0
	VALID_VIDEO_FORMAT=1
	;;
    avi|divx|m4v|mkv|ogm)
	CONVERSION_REQUIRED=1
	VALID_VIDEO_FORMAT=1
	;;
esac

if [ $VALID_VIDEO_FORMAT = 0 ]
then
    echo "Not a video file"
    exit 1
fi

FILENAME_WITHOUT_EXTENSION=`echo "${SOURCE_FILE%.*}"`
SRT_FILENAME="$FILENAME_WITHOUT_EXTENSION".srt

NO_SRT=1
if [ -f "$SRT_FILENAME" ]
then
    NO_SRT=0
fi

echo "Success! $SOURCE_FILE; NO_SRT=${NO_SRT}; CONVERSION_REQUIRED=$CONVERSION_REQUIRED"
