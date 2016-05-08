#!/bin/sh

# Install all the "base" files. Right now, includes:
# dotfiles
# scripts
# convert_video (installs in ~/opt/convert_video)

################
# Dotfiles
################


# emacs.d
cd ~/source/atlantis/dotfiles
mkdir -p ~/.emacs.d
cp emacs.d/* ~/.emacs.d

# git .ignore
mkdir -p ~/.config/git
cp ~/source/atlantis/dotfiles/gitignore ~/.config/git/ignore

# xsession
cp ~/source/atlantis/dotfiles/xsession ~/.xsession

# crontab
# Right now, I do not auto-install the crontab.
# I should do that someday though

################
# scripts
################

cd ~/source/atlantis/scripts
cp * ~/bin/

################
# scripts
################
mkdir -p ~/opt/
cd ~/source/atlantis/scripts
cp -r convert_media ~/opt/
