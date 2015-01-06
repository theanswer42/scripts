#!/bin/sh

GARMIN_SOURCE=~/source/garmin
ORIGIN_DATA_DIRECTORY=~/.config/garmin-extractor/3867192060
DATA_DIRECTORY=~/activities
BACKUP_DIRECTORY=~/Dropbox/activities

echo "Hello world"
cd ${GARMIN_SOURCE}
python ./garmin.py
cp -n ${ORIGIN_DATA_DIRECTORY}/* ${DATA_DIRECTORY}/
cp -n ${ORIGIN_DATA_DIRECTORY}/* ${BACKUP_DIRECTORY}/
