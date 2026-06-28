#!/usr/bin/bash

set -euo pipefail

###############################################################################
# Regenerate initramfs (Plymouth boot splash)
###############################################################################
# The Plymouth boot splash shown during EARLY boot reads its theme/watermark
# from the initramfs, not from /usr. The Bluefin base bakes ITS watermark into
# the initramfs at base-build time, so swapping /usr/share/plymouth/.../
# watermark.png in 15-branding.sh alone leaves the old Bluefin watermark on the
# boot screen. Rebuilding the initramfs here re-embeds the spinofin watermark.
#
# This regenerates an existing artifact -- it installs NO packages, so it does
# not touch the no-layering policy. Mirrors the base's 19-initramfs.sh.
#
# NOTE: requires the branding watermark to already be in place, so this MUST run
# AFTER 15-branding.sh in the Containerfile.
###############################################################################

echo "::group:: regenerate initramfs (plymouth)"

# Exactly one kernel is shipped in the image; take its modules dir as the kver.
# Use a glob rather than `ls | grep` (SC2010).
QUALIFIED_KERNEL=""
for moddir in /usr/lib/modules/[0-9]*; do
    [[ -d "${moddir}" ]] || continue
    QUALIFIED_KERNEL="${moddir##*/}"
    break
done
if [[ -z "${QUALIFIED_KERNEL}" ]]; then
    echo "ERROR: could not determine kernel version under /usr/lib/modules" >&2
    exit 1
fi
echo "kernel: ${QUALIFIED_KERNEL}"

export DRACUT_NO_XATTR=1
/usr/bin/dracut --no-hostonly --kver "${QUALIFIED_KERNEL}" --reproducible -v \
    --add ostree -f "/usr/lib/modules/${QUALIFIED_KERNEL}/initramfs.img"
chmod 0600 "/usr/lib/modules/${QUALIFIED_KERNEL}/initramfs.img"

echo "::endgroup::"
echo "initramfs regenerated with spinofin plymouth watermark"
