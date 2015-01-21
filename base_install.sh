#!/bin/sh

# Install all the "base" files. Right now, includes:
# dotfiles
# scripts

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


# crontab
# Right now, I do not auto-install the crontab.
# I should do that someday though

################
# scripts
################

cd ~/source/atlantis/scripts
cp * ~/bin/
