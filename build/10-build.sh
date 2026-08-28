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

# DO NOT re-copy @projectbluefin/common's just files over the base image's.
#
# The base here is the *full* Bluefin image, which is itself built from
# @projectbluefin/common and therefore already ships a complete, working
# /usr/share/ublue-os/just/ (00-entry.just, changelog.just, system.just, ...).
# Copying common's copies over them was pure redundancy -- the exact
# redundancy the Containerfile's base-image note already flags as a cleanup
# candidate -- because finpilot's template assembles from a *bare* base that
# has no just files of its own. spinofin does not.
mkdir -p /usr/share/ublue-os/just/

echo "::endgroup::"

echo "::group:: Copy Custom Files"

# Copy Brewfiles to standard location
mkdir -p /usr/share/ublue-os/homebrew/
cp /ctx/custom/brew/*.Brewfile /usr/share/ublue-os/homebrew/

# Consolidate Just Files
# Single blank-line separator (one `\n`, on top of each fragment's own
# trailing newline) -- matches `just --fmt`'s canonical style of exactly one
# blank line between top-level items. Two `\n`s here previously produced a
# double blank line at every file boundary, which `just --fmt --check`
# reports as a diff against the file `just` itself would produce -- i.e. the
# merged file this line builds (the actual justfile shipped in the image and
# parsed by `ujust` at runtime) failed formatting validation, even though
# every individual fragment under custom/ujust/ passed it. See
# .github/workflows/validate-justfiles.yml, which now builds and validates
# this exact concatenation (not just the fragments) so a mismatch here is
# caught in CI instead of only being visible after a real build.
find /ctx/custom/ujust -iname '*.just' -exec printf "\n" \; -exec cat {} \; >>/usr/share/ublue-os/just/60-custom.just

# Fail the build if any shipped justfile contains a NUL byte.
#
# `-a` is REQUIRED and not cosmetic: without it grep classifies a file as
# binary *because* it contains a NUL and reports no match.
nul_hits=""
for justfile in /usr/share/ublue-os/just/*.just; do
    if LC_ALL=C grep -qaP '\x00' "${justfile}"; then
        nul_hits="${nul_hits} ${justfile}"
    fi
done
if [ -n "${nul_hits}" ]; then
    echo "ERROR: NUL byte(s) found in shipped justfile(s):${nul_hits}" >&2
    echo "This would break ALL ujust recipes at runtime. Refusing to ship." >&2
    exit 1
fi

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

# Copy the pipx tool list (the host-side Python tooling declaration).
# Like the brew/flatpak/distrobox copies above, this is just a file copy --
# no packages are installed on the host here. The tools it declares are
# installed at runtime by `ujust install-pipx-tools` into the user's
# ~/.local (isolated pipx venvs), which does not touch the image and does
# not violate the no-layering policy.
mkdir -p /usr/share/spinofin/pipx/
cp /ctx/custom/pipx/*.pipx /usr/share/spinofin/pipx/

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
