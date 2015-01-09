#!/bin/sh

FFMPEG=/opt/ffmpeg/bin/ffmpeg
FFPROBE=/opt/ffmpeg/bin/ffprobe
TMPDIR=~/tmp/video_conversion
mkdir -p "$TMPDIR"

get_stream_id()
{
    echo $1 | sed -n -e's/.*Video:\ \([a-zA-Z0-9]*\).*/\1/gp'
}

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

OUTPUT_VIDEO_NAME="$FILENAME_WITHOUT_EXTENSION".mp4

if [ -f "$OUTPUT_VIDEO_NAME" ]
then
    echo "Encoded video already exists: $OUTPUT_VIDEO_NAME\n. Skipping"
    CONVERSION_REQUIRED=0
fi

# Building the options
# 1. for Video, This is straightforward:
# if(video stream is encoded with x264) { copy }
# else { add x264 with options }

# What are the input video codecs i see?
# ansi mpeg4 msmpeg4v3 none theora
#
# out of these, mpeg4 is straightforward
# ansi - my mistake.. all text files are treated as "ansi" video streams
# msmpeg4v3 (MP43) seems just another video codec
# theora - should be no problemo
# none - there's not a lot with this, so this is strange. lets see how this goes.

# So lets get the streams first
STREAMS="$TMPDIR"/streams
$FFPROBE "$SOURCE_FILE" 2>&1 | grep Stream > $STREAMS 

VIDEO_MAP=""
VIDEO_OPTIONS=""
H264_STREAM=get_stream_id(cat $STREAMS | grep "h264")
if [ H264_STREAM != "" ]
then
    VIDEO_MAP="-map $H264_STREAM"
    VIDEO_OPTIONS=" -c:${H264_STREAM} copy"
fi

X264_ENCODE_OPTIONS="libx264 -preset slow -crf 18"
AUDIO_OPTIONS="-c:a copy"
SUBTITLES_OPTIONS="-c:s mov_text"
INPUT_FILE_OPTIONS="-fix_sub_duration"

echo $FFMPEG "$INPUT_FILE_OPTIONS" -i "$SOURCE_FILE" "$GLOBAL_STREAM_SELECTION" "$VIDEO_OPTIONS" "$AUDIO_OPTIONS" "$SUBTITLES_OPTIONS" "$OUTPUT_VIDEO_NAME"

