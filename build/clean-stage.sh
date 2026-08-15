#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# CLEAN_ROOT: filesystem prefix applied to all paths.
# Defaults to "/" so the variable is never empty (satisfies SC2115).
# Set to a temp directory during unit tests.
CLEAN_ROOT="${CLEAN_ROOT:-/}"

# NOTE: no dnf5 calls here, unlike the upstream template.
#
# The template reverts `keepcache` and clears versionlocks because its build
# sets both. spinofin's no-layering policy means it sets neither: nothing is
# installed at build time, so there is no cache to disable and no versionlock
# to clear (the Bluefin base already runs its own `versionlock clear` at the
# end of its build, so none are inherited either).
#
# Beyond being inert, `dnf5 config-manager setopt keepcache=0` was the step
# that failed the build: it is the first thing to *read* /etc/dnf/dnf.conf
# after the Containerfile's own `config-manager setopt` had rewritten it, and
# it died on the malformed result ("Missing '=' on line 5"). That writer is
# now gone; this reader goes with it. Keeping clean-stage.sh dnf-free also
# makes it survive the Track A -> Track B move to a base with no package
# manager, where any dnf5 call here would fail outright.

# This comes last because we can't *ever* afford to ship fedora flatpaks on the image
systemctl disable flatpak-add-fedora-repos.service
systemctl mask flatpak-add-fedora-repos.service
rm -f "${CLEAN_ROOT}/usr/lib/systemd/system/flatpak-add-fedora-repos.service"

rm -rf "${CLEAN_ROOT}/.gitkeep"
find "${CLEAN_ROOT}/var"/* -maxdepth 0 -type d \! -name cache -exec rm -fr {} \;

# bootc forbids baking persistent content into /var (it must ship empty,
# or only contain systemd-tmpfiles.d-seeded entries), so this must not
# create anything that wasn't already there. /var/cache is often entirely
# absent at this point -- the libdnf5/rpm-ostree caches used during the
# package-install step are cache-mounted and excluded from the final
# layer by design -- so guard with an existence check instead of relying
# on glob expansion, which leaves a literal unexpanded string and breaks
# `find` when nothing matches.
if [ -d "${CLEAN_ROOT}/var/cache" ]; then
    find "${CLEAN_ROOT}/var/cache" -mindepth 1 -maxdepth 1 -type d \! -name libdnf5 \! -name rpm-ostree -exec rm -fr {} \;
fi

# Clear tmpfs-backed runtime directories without deleting the directories
# themselves. Buildah may have bind mounts in these paths during RUN, so
# replacing the mountpoint can fail with EBUSY.
for runtime_dir in tmp boot; do
    mkdir -p "${CLEAN_ROOT:?}/${runtime_dir}"
    find "${CLEAN_ROOT:?}/${runtime_dir}" -mindepth 1 -maxdepth 1 -print0 |
        while IFS= read -r -d '' entry; do
            if mountpoint -q "${entry}" 2>/dev/null; then
                continue
            fi
            rm -rf "${entry}"
        done
done

# /run can contain nested bind mounts created by the build container. Walk it
# depth-first so we can remove image-owned files like /run/dnf while leaving
# mounted files and any directories that still contain them alone.
mkdir -p "${CLEAN_ROOT:?}/run"
find "${CLEAN_ROOT:?}/run" -mindepth 1 -depth -print0 |
    while IFS= read -r -d '' entry; do
        if mountpoint -q "${entry}" 2>/dev/null; then
            continue
        fi
        if [[ -d "${entry}" ]]; then
            rmdir "${entry}" 2>/dev/null || true
            continue
        fi
        rm -f "${entry}"
    done

echo "::endgroup::"
