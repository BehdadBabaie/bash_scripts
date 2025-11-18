#!/bin/bash

# Backup pacman config file
sudo cp /etc/pacman.conf /etc/pacman.conf.bak

# Do the magic:
#  - Ucomment Color
#  - Add ILoveCandy right below it
#  - Uncomment VerbosePkgLists
sudo sed -i '
  /^[[:space:]]*#*Color/ {
    s/^#[[:space:]]*//    # uncomment Color
    a ILoveCandy          # add ILoveCandy on the next line
  }
  /^[[:space:]]^\*#VerbosePkgLists/ s/^#[[:space:]]*//
' /etc/pacman.conf


echo "Done! pacman now has:"
echo "  . Color enabled"
echo "  . ILoveCandy progress bar "
echo "  . VerbosePkgLists (prettier package lists)"
echo "Original file backed up to /etc/pacman.conf.bak"
