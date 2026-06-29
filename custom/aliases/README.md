# spinofin host-shell aliases

Baked-in shell helpers for working with the shared Kali toolbox container
from the host shell, shipped the same way as `custom/branding/` -- a
`system_files/` tree copied verbatim into the image at build time. No setup
step, no `ujust` recipe to run: present as soon as you boot the image.

## No-layering posture

Nothing here installs a package. It is a single file drop into
`/etc/profile.d/`, which Fedora's `/etc/bashrc` sources for both login and
interactive non-login bash shells (e.g. a fresh GNOME Terminal tab) -- the
standard Fedora/RHEL convention. So this does not trip the
`no-layering-check.yml` guard (it only greps for package-manager install
calls) and there is nothing to unwind at the eventual Track-B (GNOME OS
bootc) migration.

**Scope note:** this targets `bash` (Bluefin's default interactive shell).
zsh does not read `/etc/profile.d` by default, so zsh users will need to
source `/etc/profile.d/spinofin-kali-aliases.sh` from their own `~/.zshrc` if
they've switched shells.

## What's provided

`system_files/etc/profile.d/spinofin-kali-aliases.sh` defines two shell
functions for running a command in the shared `spinofin-kali` container
without typing the full `distrobox enter --root spinofin-kali -- ...` --
the same `distrobox enter` pattern already used throughout
`custom/ujust/kali-container.just` and the impacket privilege caveat in the
main README:

- `kali <cmd>` — run `<cmd>` in the container as your user. No args drops
  you into an interactive shell (same as `ujust enter-kali`).
- `kalisudo <cmd>` — same, but as root in the container (needed for raw
  sockets / low ports, e.g. some impacket tools -- see the README's
  impacket privilege caveat).

Both error harmlessly toward `ujust setup-kali` if the container hasn't been
created yet, rather than letting `distrobox enter` fall through to its
default behavior: offering to create a new container under that same name
using the *host's* default image (Fedora) instead of Kali.

## Layout

```
custom/aliases/
└── system_files/
    └── etc/
        └── profile.d/
            └── spinofin-kali-aliases.sh   # copied verbatim to /etc/profile.d/
```

Wired into the image by `build/17-aliases.sh`, a straight `cp -a` copy --
mirrors `custom/branding/`'s mechanism exactly, just for a different
on-image path.
