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
FROM ghcr.io/projectbluefin/common:latest@sha256:4e8ae3e5a52fe2ef75b2c5d73c4e5009c0f01f8dadc1e43c95e8f7b6762759eb AS common
FROM ghcr.io/ublue-os/brew:latest@sha256:8f952ae54585db9f855a306ef365e13609ed7c7944b12b823ba7d5ce8e1a145b AS brew

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
FROM ghcr.io/ublue-os/bluefin:stable@sha256:9debc087a4468afebbbbb0d1a4f6c51bb93e6095b36a6455e24bab57fe75e13d

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

# NOTE: there is deliberately NO dnf configuration step here.
#
# The finpilot template sets `dnf5 config-manager setopt keepcache=1
# install_weak_deps=0` at this point to warm the package cache for its
# `dnf5 install` calls. spinofin has no such calls -- the no-layering policy
# means nothing is ever installed at build time -- so both options were inert,
# and the step was pure template inheritance.
#
# It was also actively harmful: `config-manager setopt` rewrites
# /etc/dnf/dnf.conf in place, and on the CI runner it left the file
# unparseable, surfacing several steps later as
#   Error in configuration file "/etc/dnf/dnf.conf" / Missing '=' on line 5
# at the *next* dnf5 invocation (clean-stage.sh), pointing nowhere near its
# own cause. Not writing the file at all is both the fix and the correct
# end state: the Track A -> Track B target (GNOME OS bootc) ships no package
# manager, so build-time dnf usage is something we want to be rid of anyway.
# See README.md, "No Build-Time Layering".

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
