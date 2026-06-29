#!/usr/bin/bash

set -euo pipefail

###############################################################################
# Host sudo prompt
###############################################################################
# Bakes a sudo prompt disambiguation file into /etc/sudoers.d/, the same way
# 15-branding.sh and 17-aliases.sh bake in their own assets: a plain file
# copy, no setup step required. See custom/sudo-prompt/README.md.
#
# This only ADDS a new file under /etc/sudoers.d/ -- it never touches the
# main /etc/sudoers file (whose own #includedir line is what makes drop-in
# files work, already enabled by default on Fedora). If sudo ever rejects
# this one file (e.g. a future edit breaks its permissions), sudo skips just
# that file with a warning rather than breaking sudo system-wide.
#
# NO-LAYERING POLICY -- see README.md
# A single file overlay. No packages are installed.
###############################################################################

echo "::group:: spinofin host sudo prompt"

# Mirrors on-image paths 1:1, so this is a straight merge-copy into /.
cp -a /ctx/custom/sudo-prompt/system_files/. /

# sudo REQUIRES files in /etc/sudoers.d/ to be owned root:root and mode 0440,
# or it silently skips them. Never trust the mode/ownership a file happens to
# carry through git or any delivery path -- set it explicitly every time.
chown root:root /etc/sudoers.d/spinofin-host-sudo-prompt
chmod 0440 /etc/sudoers.d/spinofin-host-sudo-prompt

echo "::endgroup::"

echo "spinofin host sudo prompt installed (/etc/sudoers.d/spinofin-host-sudo-prompt)"
