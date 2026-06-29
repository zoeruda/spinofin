#!/usr/bin/bash

set -euo pipefail

###############################################################################
# Host-shell aliases
###############################################################################
# Bakes spinofin's `kali` / `kalisudo` shell functions into the image via
# /etc/profile.d, the same way 15-branding.sh bakes in artwork: a plain file
# copy, no setup step required.
#
# NO-LAYERING POLICY -- see README.md
# This is a single file overlay. No packages are installed, so this does not
# violate the no-layering policy (nothing to unwind at the Track A -> Track B
# migration).
#
# See custom/aliases/README.md for what's provided and the bash-only scope note.
###############################################################################

echo "::group:: spinofin host-shell aliases"

# Mirrors on-image paths 1:1, so this is a straight merge-copy into /.
cp -a /ctx/custom/aliases/system_files/. /

echo "::endgroup::"

echo "spinofin host-shell aliases installed (/etc/profile.d/spinofin-kali-aliases.sh)"
