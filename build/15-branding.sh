#!/usr/bin/bash

set -euo pipefail

###############################################################################
# Branding
###############################################################################
# Applies spinofin's OS-identity branding: wallpapers, boot splash (Plymouth
# watermark), GDM login logo, panel logo icon, and fastfetch terminal logo.
# Also ships an XDG autostart entry (etc/xdg/autostart/) that seeds branding
# into each account's own dconf db on first graphical login, so spinofin's
# marks apply out of the box while still leaving them changeable (and
# the change persistent) by the user afterward -- see

# custom/branding/README.md, "User-Customizable Panel Logo". No new systemd
# unit is authored for this -- the autostart entry is just another file in
# system_files/, picked up by the merge-copy in step 2 below like everything
# else in this script; GNOME session startup (not anything spinofin wires up
# itself) is what runs it.
#
# NO-LAYERING POLICY -- see README.md
# Everything here is either a FILE OVERWRITE of artwork the base image already
# ships, or a dconf default keyfile. No packages are installed, so this does
# not violate the no-layering policy (and survives the Track A -> Track B
# migration with nothing to unwind).
#
# Asset sources and the per-surface spec live in custom/branding/README.md.
###############################################################################

shopt -s nullglob

echo "::group:: spinofin branding"

# 1. Preserve Bluefin's stock fastfetch.json BEFORE we overwrite it below.
#    We overwrite this exact path with our own ASCII logo config in step 2,
#    which means the base image's own version -- whatever currently drives
#    Bluefin's dino-shuffle logo -- would otherwise be gone from spinofin's
#    ostree commit entirely, with no way back short of a full rebase to
#    ghcr.io/ublue-os/bluefin. Stashing a copy here means a user can restore
#    it with a single `cp`, without us having to reverse-engineer or hardcode
#    Bluefin's own shuffle config (which may change upstream over time --
#    this always captures whatever the pinned base currently ships). Read-
#    only reference copy, same posture as the other /usr/share/spinofin
#    manifests -- not meant to be hand-edited, just copied back over
#    /etc/ublue-os/fastfetch.json by a user who wants the dino back.
if [ -f /etc/ublue-os/fastfetch.json ]; then
    mkdir -p /usr/share/spinofin/fastfetch
    cp /etc/ublue-os/fastfetch.json /usr/share/spinofin/fastfetch/bluefin-fastfetch.json.orig
fi

# 2. Lay down all branding files. system_files/ mirrors the on-image paths 1:1,
#    so this is a straight merge-copy into /. `cp -a … /.` copies the *contents*
#    of system_files into / and overwrites the upstream assets in place.
cp -a /ctx/custom/branding/system_files/. /

# Set default wallpaper to match the current build month (Bluefin canonical pattern)
current_month=$(date +%m)
current_wp_file=""
for wp in /usr/share/backgrounds/spinofin/"${current_month}"-spinofin-*.jpg; do
    if [ -f "$wp" ]; then
        current_wp_file="$wp"
        break
    fi
done

if [ -n "$current_wp_file" ]; then
    if [ -f /etc/dconf/db/distro.d/99-spinofin-branding ]; then
        sed -i -E "s|/usr/share/backgrounds/spinofin/[0-9]{2}-spinofin-[^']+\.jpg|${current_wp_file}|g" \
            /etc/dconf/db/distro.d/99-spinofin-branding
    fi
    if [ -f /usr/share/glib-2.0/schemas/zz1-spinofin-modifications.gschema.override ]; then
        sed -i -E "s|/usr/share/backgrounds/spinofin/[0-9]{2}-spinofin-[^']+\.jpg|${current_wp_file}|g" \
            /usr/share/glib-2.0/schemas/zz1-spinofin-modifications.gschema.override
    fi
fi

# 3. Compile GLib schemas and dconf databases so overrides take effect on build.
if command -v glib-compile-schemas >/dev/null 2>&1; then
    glib-compile-schemas /usr/share/glib-2.0/schemas
fi
dconf update || echo "WARN: dconf update failed at build; dconf-update.service will retry on boot"

# 4. Refresh the hicolor icon cache so the custom symbolic panel icon resolves
#    by name (menuicon-setting='spinofin-logo-symbolic').
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f /usr/share/icons/hicolor >/dev/null 2>&1 || true
fi

echo "::endgroup::"

echo "spinofin branding applied"
