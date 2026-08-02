###############################################################################
# PROJECT NAME CONFIGURATION
###############################################################################
# Name: spinofin
#
# IMPORTANT: Change "finpilot" above to your desired project name.
# This name should be used consistently throughout the repository in:
#   - Justfile: export IMAGE_NAME := env("IMAGE_NAME", "your-name-here")
#   - README.md: # your-name-here (title)
#   - artifacthub-repo.yml: repositoryID: your-name-here
#   - custom/ujust/README.md: localhost/your-name-here:stable (in bootc switch example)
#
# The project name defined here is the single source of truth for your
# custom image's identity. When changing it, update all references above
# to maintain consistency.
###############################################################################

###############################################################################
# MULTI-STAGE BUILD ARCHITECTURE
###############################################################################
# This Containerfile follows the Bluefin architecture pattern as implemented in
# @projectbluefin/distroless. The architecture layers OCI containers together:
#
# 1. Context Stage (ctx) - Combines resources from:
#    - Local build scripts and custom files
#    - @projectbluefin/common - Desktop configuration shared with Aurora
#    - @ublue-os/brew - Homebrew integration
#
# 2. Base Image Options (edit the FROM line below):
#    - `quay.io/fedora-ostree-desktops/silverblue:44` (Fedora 44 and GNOME)
#    - `quay.io/fedora-ostree-desktops/base-main:44` (Fedora 44, no desktop)
#    - `quay.io/centos-bootc/centos-bootc:stream10` (CentOS-based)
#
# See: https://docs.projectbluefin.io/contributing/ for architecture diagram
###############################################################################

# OCI context images - imported below and pinned directly in their FROM lines.
# The base image is pinned in the FROM line below and updated by Renovate.
FROM ghcr.io/projectbluefin/common:latest@sha256:ed54b94969646b0655dfc3d7236d484af26a80fff6b97f013eee805d130a3286 AS common
FROM ghcr.io/ublue-os/brew:latest@sha256:07799dfe9ed44812a63d1b23c74e3e30b758a976f647032d916c34daf30f60a4 AS brew

# Context stage - combine local and imported OCI container resources
FROM scratch AS ctx

COPY build /build
COPY custom /custom

# Copy from OCI containers to distinct subdirectories to avoid conflicts
COPY --from=common /system_files /oci/common
COPY --from=brew /system_files /oci/brew

# Base Image - full Bluefin (Fedora Silverblue + GNOME + Bluefin desktop
# config, fastfetch, fonts, codecs, ujust ecosystem, akmods).
#
# NOTE: This is a *final* Bluefin image, not a bare base. finpilot's ctx
# stage still copies /oci/common and /oci/brew below, which Bluefin already
# contains -- that redundancy is intentional/accepted for now (we'll be
# overriding desktop config with Kali-like settings in a later phase, so
# keeping finpilot's bare-base assembly pristine isn't worth it yet).
# Cleanup candidate later: drop the redundant common/brew COPYs once the
# build scripts no longer depend on those /oci paths.
#
# Pinned to :stable for now; Renovate will replace this with a
# :stable@sha256:... digest pin on its first run after push.
FROM ghcr.io/ublue-os/bluefin:stable@sha256:892f67807a66bb2bcd680b6c74d028cd4a9327b8dd892ef3d6004a2a5baaa031

# Image identity - these define how bootc, fastfetch, and the ublue ecosystem
# recognize your image. Change these to match your project name.
ARG IMAGE_NAME="spinofin"
ARG IMAGE_VENDOR="zoeruda"
# Human-readable name shown in os-release PRETTY_NAME (GNOME About, the Anaconda
# installer title, and the bootloader entry). 00-image-info.sh reads this from
# the build env; without it PRETTY_NAME falls back to the template's "My Custom OS".
ARG IMAGE_PRETTY_NAME="spinofin"
# os-release LOGO icon name -> GNOME Settings > About logo. The icon by this
# name is shipped by 15-branding.sh (custom/branding apps/spinofin-logo.svg).
ARG IMAGE_LOGO="spinofin-logo"
ARG UBLUE_IMAGE_TAG="stable"
ARG BASE_IMAGE_NAME="bluefin"
ARG FEDORA_MAJOR_VERSION="44"
ARG VERSION=""

### MODIFICATIONS
## Make modifications desired in your image and install packages by modifying the build scripts.
## The following RUN directives mount the ctx stage which includes:
##   - Local build scripts from /build
##   - Local custom files from /custom
##   - Files from @projectbluefin/common at /oci/common (includes branding/artwork content)
##   - Files from @ublue-os/brew at /oci/brew
## Scripts are run in numerical order (10-build.sh, 20-example.sh, etc.)

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/00-image-info.sh

# Set dnf options before build scripts (persists across subsequent RUN layers)
# NOTE: no-layering policy in effect -- this repo does not call `dnf5 install`
# in build/*.sh. This line only sets cache options and is otherwise inert.
# See README.md for the full rationale and the Track A -> Track B
# (GNOME OS bootc, no package manager) migration plan this enables.
RUN dnf5 config-manager setopt keepcache=1 install_weak_deps=0

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=cache,dst=/var/cache/rpm-ostree \
    --mount=type=secret,id=GITHUB_TOKEN \
    --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/10-build.sh

# Branding: boot splash, GDM login logo, panel logo icon, fastfetch logo.
# File overwrites + dconf defaults only -- no package layering. See
# custom/branding/README.md for the per-surface spec.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/15-branding.sh

# Regenerate initramfs so the Plymouth boot splash uses the spinofin watermark
# (early-boot splash reads the initramfs, not /usr). Must run after branding.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/16-initramfs.sh

# Host-shell aliases (kali, kalisudo) for the Kali toolbox container -- a
# single /etc/profile.d file overlay, no setup step required. See
# custom/aliases/README.md.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/17-aliases.sh

# Host sudo prompt disambiguation (host vs. Kali container) -- a single
# /etc/sudoers.d file overlay, no setup step required. See
# custom/sudo-prompt/README.md.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/18-sudo-prompt.sh

### CLEANUP
## Use Bluefin's clean-stage.sh to remove build artifacts before linting.
## /run is deliberately not mounted as tmpfs here: clean-stage.sh must remove
## image-layer files such as /run/dnf so bootc lint's nonempty-run-tmp check
## passes. The script tolerates busy Buildah bind mounts while clearing contents.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    --mount=type=tmpfs,dst=/boot \
    /ctx/build/clean-stage.sh

### /opt
## Makes /opt writeable by default. Needs to be here to make the main image
## build strict (no /opt there). This is for downstream images/stuff like k0s.
## If you need /opt as an immutable real directory for build-time packages
## (e.g. google-chrome, docker-desktop), replace the next line with:
##   RUN rm /opt && mkdir /opt
RUN rm -rf /opt && ln -s /var/opt /opt

### INIT
## Required for bootc images
CMD ["/sbin/init"]

### LINTING
## Verify final image and contents are correct. --fatal-warnings catches issues.
RUN bootc container lint --fatal-warnings
