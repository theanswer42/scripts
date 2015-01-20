#!/bin/sh

# only one parameter:
# --create-iso
# when used, I will do the regular backup, then create an iso image and
# put it on the desktop.
# all files are then moved into an "archive" folder.
# The signal to remove the archive folder is removing the iso image from the
# Desktop.

BACKUP_LOCATION=~/backup

# Things to back up are always relative paths to home
# This could probably be moved into a config of some sort
THINGS_TO_BACKUP="notes source activities Documents"

BACKUP_TS=`date +"%Y-%m-%d_%H-%M-%S"`

# 1. Create a new set of backups in backup/current
mkdir -p "$BACKUP_LOCATION"/current

cd ~
echo -n "working"
for DIRNAME in $THINGS_TO_BACKUP; do
    # -J is more compact, but -j is still a bit more available.
    ARCHIVE_NAME="${BACKUP_LOCATION}/current/${DIRNAME}_${BACKUP_TS}"
    tar -cjvf "${ARCHIVE_NAME}.tar.bz2" "$DIRNAME" > /dev/null 2>&1
    md5sum "${ARCHIVE_NAME}.tar.bz2" > "${ARCHIVE_NAME}.tar.bz2.md5sum"
    echo -n "."
done;
echo "done"

# 2. if no create_iso, we're done
if [ "$1" != "--create-iso" ]; then
    exit 0
fi;

# 3. OK. First step is to create an iso image from the "current" dir.
mkdir -p "${BACKUP_LOCATION}/images"
mkdir -p "${BACKUP_LOCATION}/archive"
IMAGE_NAME="${BACKUP_TS}"
genisoimage -V "{IMAGE_NAME}" -r "${BACKUP_LOCATION}/current" | gzip > "${BACKUP_LOCATION}/images/${IMAGE_NAME}.iso.gz"
mv "${BACKUP_LOCATION}/current" "${BACKUP_LOCATION}/archive/${IMAGE_NAME}"
mkdir -p "${BACKUP_LOCATION}/current"

# 4. For each directory in backup/archive, check if the image still exists.
#    If not, remove the archive.
cd "${BACKUP_LOCATION}/archive"
for ARCH_NAME in *; do
    echo $ARCH_NAME
    if [ ! -f "${BACKUP_LOCATION}/images/${ARCH_NAME}.iso.gz" ]; then
	echo "Looks like ${ARCH_NAME} has been processed. Removing archives."
	rm -rf "${BACKUP_LOCATION}/archive/${ARCH_NAME}";
    fi
done;
