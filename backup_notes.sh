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
tar -cJvf ${archive_name} ${NOTESDIR}
md5sum ${archive_name} > ${archive_name}.md5sum

cp ${archive_name} ${archive_name}.md5sum ${BACKUPDIR}/

rm ${TMPDIR}/*


