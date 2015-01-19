#!/bin/sh

# Install all the "base" files. Right now, includes:
# dotfiles
# scripts

################
# Dotfiles
################

cd ~/source/atlantis/dotfiles
mkdir -p ~/.emacs.d
cp emacs.d/* ~/.emacs.d

# crontab
# Right now, I do not auto-install the crontab.
# I should do that someday though

################
# scripts
################

cd ~/source/atlantis/scripts
cp * ~/bin/
