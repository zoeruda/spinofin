# spinofin sudo prompt disambiguation

Baked-in sudo prompt customization for the host, shipped the same way as
`custom/branding/` and `custom/aliases/` -- a `system_files/` tree copied
verbatim into the image at build time. No setup step.

## The problem this solves

Running `sudo` on the host and running `sudo` inside the shared Kali
container (e.g. via `kalisudo <cmd>` or `distrobox enter --root spinofin-kali
-- sudo <cmd>`) both show the *same* default prompt, `[sudo] password for
<user>: `, with no indication of which password is being asked for. This
file makes that explicit by adding the hostname to the prompt:

```
[sudo] password for zoe (on spinofin-kali): #  inside the container
[sudo] password for zoe (on my-laptop): #      on the host
```

## How it works

`Defaults passprompt="[sudo] password for %p (on %h): "` uses sudo's `%p`
(user whose password is requested) and `%h` (local hostname) escapes -- see
`man 5 sudoers`. The **same line** is deployed in two places, and resolves
to two different, correct strings because `%h` differs by context:

- **Host** (this directory): dropped at `/etc/sudoers.d/spinofin-host-sudo-prompt`
  by `build/18-sudo-prompt.sh`, so `%h` is the host's real hostname.
- **Container**: written by `ujust setup-kali` (see
  `custom/ujust/kali-container.just`) to
  `/etc/sudoers.d/spinofin-sudo-prompt` *inside* `spinofin-kali`. The
  container's hostname is explicitly pinned to `spinofin-kali` via
  `hostname=spinofin-kali` in `custom/distrobox/spinofin-kali.ini`, so `%h`
  there is always literally `spinofin-kali`, regardless of whatever
  hostname podman/distrobox would otherwise default to.

## Why this is safe

This only ever **adds a new file** under `/etc/sudoers.d/` -- it never edits
the main `/etc/sudoers` file (whose own `#includedir /etc/sudoers.d` line is
what makes drop-in files work, and which is already enabled by default on
both Fedora and Debian/Kali). If a sudoers.d file is ever malformed or has
the wrong permissions, sudo independently skips *that one file* with a
warning -- it does not break sudo for anything else. Two requirements are
non-negotiable for a sudoers.d file to be honored at all, both handled
explicitly rather than trusted from git/transfer:

- **Mode `0440`, owned `root:root`** -- `build/18-sudo-prompt.sh` sets this
  explicitly after the file copy (never assume the committed mode survives).
- **No dot in the filename** -- sudo silently ignores any file in
  `/etc/sudoers.d/` whose name contains a `.` or ends in `~`.

## No-layering posture

A single file overlay. No packages installed, nothing to unwind at the
Track A -> Track B (GNOME OS bootc) migration.

## Layout

```
custom/sudo-prompt/
└── system_files/
    └── etc/
        └── sudoers.d/
            └── spinofin-host-sudo-prompt   # copied verbatim to /etc/sudoers.d/
```
