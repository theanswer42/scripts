#!/bin/sh

TMPDIR=~/tmp
mkdir -p ${TMPDIR}/notes_backups

TMPDIR=${TMPDIR}/notes_backups

NOTESDIR=notes
BACKUPDIR=~/Dropbox/notes_backups
mkdir -p ${BACKUPDIR}

ts=`date +"%Y_%m_%d"`
archive_name=${TMPDIR}/notes_${ts}.tar.Z

cd ~
tar -cJvf ${archive_name} ${NOTESDIR} > /dev/null
md5sum ${archive_name} > ${archive_name}.md5sum

last_backup_md5_file=`ls -c ${BACKUPDIR}/*.md5sum | head -1`
last_backup_md5=`cat ${last_backup_md5_file} | cut -f1 -d" "`
if grep ${last_backup_md5} ${archive_name}.md5sum > /dev/null; then
    echo "No Changes since last backup."
else
    echo "New changes detected. Copying."
    cp ${archive_name} ${archive_name}.md5sum ${BACKUPDIR}/
fi
rm ${TMPDIR}/*


