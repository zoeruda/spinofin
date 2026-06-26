#!/usr/bin/bash

set -euo pipefail

###############################################################################
# Main Build Script
###############################################################################
# This script follows the @ublue-os/bluefin pattern for build scripts.
# It uses set -euo pipefail for strict error handling.
###############################################################################

# Source helper functions
# shellcheck source=/dev/null
source /ctx/build/copr-helpers.sh

# Enable nullglob for all glob operations to prevent failures on empty matches
shopt -s nullglob

echo "::group:: Copy Bluefin Config from Common"

# Copy just files from @projectbluefin/common (includes 00-entry.just which imports 60-custom.just)
mkdir -p /usr/share/ublue-os/just/
shopt -s nullglob
cp -r /ctx/oci/common/bluefin/usr/share/ublue-os/just/* /usr/share/ublue-os/just/
shopt -u nullglob

echo "::endgroup::"

echo "::group:: Copy Custom Files"

# Copy Brewfiles to standard location
mkdir -p /usr/share/ublue-os/homebrew/
cp /ctx/custom/brew/*.Brewfile /usr/share/ublue-os/homebrew/

# Consolidate Just Files
find /ctx/custom/ujust -iname '*.just' -exec printf "\n\n" \; -exec cat {} \; >>/usr/share/ublue-os/just/60-custom.just

# Copy Flatpak preinstall files
mkdir -p /usr/share/flatpak/preinstall.d/
cp /ctx/custom/flatpaks/*.preinstall /usr/share/flatpak/preinstall.d/

# Copy Distrobox manifests (the Kali toolbox container declaration).
# This is just a file copy -- no packages are installed on the host. The
# tools declared inside the manifest are installed via apt INSIDE the
# container at provisioning time, which does not touch the host image and
# does not violate the no-layering policy.
mkdir -p /usr/share/spinofin/distrobox/
cp /ctx/custom/distrobox/*.ini /usr/share/spinofin/distrobox/

echo "::endgroup::"

echo "::group:: Install Packages"

# -----------------------------------------------------------------------
# NO-LAYERING POLICY -- see README.md
#
# This fork intentionally does not add packages via dnf5/rpm-ostree/COPR.
# The goal is a base image that can later be swapped for a true GNOME OS
# bootc image (which has no system package manager at all) without having
# to unwind a pile of build-time package layering first.
#
# New tools go in one of these places instead:
#   - custom/brew/*.Brewfile       CLI tools, installed at runtime via
#                                   `ujust install-default-apps` etc.
#   - custom/flatpaks/*.preinstall GUI apps, installed on first boot
#
# The `dnf5 config-manager setopt ...` line in the Containerfile is left
# in place because it only sets cache options -- it does not install
# anything, so it doesn't violate this policy.
# -----------------------------------------------------------------------

echo "::endgroup::"

echo "::group:: System Configuration"

# Enable/disable systemd services
systemctl enable podman.socket
# Example: systemctl mask unwanted-service

echo "::endgroup::"

# Restore default glob behavior
shopt -u nullglob

echo "Custom build complete!"
