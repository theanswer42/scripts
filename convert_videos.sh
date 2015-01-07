#!/bin/sh

# Inputs:
# directory-name : all the files (media, srt, etc)
# name: string
# series: (y/n)
# season: number

# Output:
# * Videos in mp4 + aac 2.0 format
# * Subtitles in separate srt files (no need for including a mov_text stream)
# * webvtt subtitles
# * appropriate directory structure:
#   name/season-#/episode-#-ep_name.mp4

# Things I don't know:
# * How do I pick the right video quality
# * How do I extract the srt in a separate output stream and not include mov_text
# * How do I get the webvtt converter

# Punted:
# * Add meta-data to the file (name, genre, other things? )


usage()
{
    cat <<EOF
    usage: $0 -d
    
    Convert videos into a format suitable for html5 video streaming
    
    Options:
    -h   Show this message
    -d   directory to import
    -n   name of the movie/show (use "" for names with whitespace)
    -s   number of the season
    -m   This is a series
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

MEDIA_TYPE="movie"
SEASON=""
SOURCE_DIR=""

while getopts "hd:n:s:m" OPTION
do
    case $OPTION in 
	h) 
	    usage
	    exit 0
	    ;;
	d)
	    SOURCE_DIR=${OPTARG}
	    ;;
	n)
	    MEDIA_NAME=${OPTARG}
	    # Filter the name
	    ;;
	s)
	    SEASON=`echo ${OPTARG} | sed -n -e 's/[0-9]//gp'`
	    MEDIA_TYPE="show"
	    ;;
	m)
	    MEDIA_TYPE="show"
	    ;;
    esac
done

if [ "$SOURCE_DIR" = "" ] || [ ! -d "$SOURCE_DIR" ]
then
    echo "directory '${SOURCE_DIR}' does not exist"
    MEDIA_TYPE="err"
fi

if [ "$MEDIA_NAME" = "" ]
then
    echo "name cannot be blank"
    MEDIA_TYPE="err"
fi

if [ "$MEDIA_TYPE" = "show" ] && [ "$SEASON" = "" ]
then
    echo "season expected for a show: must be a number"
    MEDIA_TYPE="err"
fi

if [ "$MEDIA_TYPE" != "movie" ] && [ "$MEDIA_TYPE" != "show" ]
then
    usage
    exit 1
fi

