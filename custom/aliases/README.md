# spinofin host-shell aliases

Baked-in shell helpers for working with the shared Kali toolbox container
from the host shell, shipped the same way as `custom/branding/` -- a
`system_files/` tree copied verbatim into the image at build time. No setup
step, no `ujust` recipe to run: present as soon as you boot the image.

## No-layering posture

Nothing here installs a package. Files are dropped into `/etc/profile.d/` and
`/etc/fish/conf.d/`, standard Fedora/RHEL drop-in directories copied verbatim
into the image root at build time. This does not trip the `no-layering-check.yml`
guard (it only greps for package-manager install calls) and there is nothing to
unwind at the eventual Track-B (GNOME OS bootc) migration.

### Multi-Shell Support (Bash, Zsh, Fish)

- **Bash & Zsh**: Sourced via `/etc/profile.d/spinofin-kali-aliases.sh` and
  `/etc/profile.d/spinofin-kalicli-aliases.sh`. Fedora's `/etc/bashrc` and
  `/etc/zshrc` automatically source all `/etc/profile.d/*.sh` files for login
  and interactive non-login shells. Functions are written using POSIX/Zsh-compatible
  flag arrays and TTY detection (`[ -t 0 ] && [ -t 1 ]`) so piped I/O works seamlessly.
- **Fish**: Sourced via `/etc/fish/conf.d/spinofin-kali-aliases.fish` and
  `/etc/fish/conf.d/spinofin-kalicli-aliases.fish`. Fish automatically
  loads scripts in `/etc/fish/conf.d/` on launch. Native Fish functions provide identical
  behavior and CLI flags.

## What's provided

### `spinofin-kali` helpers (distrobox)

- `kali <cmd>` — run `<cmd>` in the `spinofin-kali` container as your user.
  No args drops you into an interactive login shell (same as `ujust enter-kali`).
- `kalisudo <cmd>` — same, but as root in the container (`distrobox enter --root spinofin-kali -- sudo ...`).
- `iskali` — report whether `spinofin-kali` exists (exit 0 = present, non-zero = not created).

Both `kali` and `kalisudo` error harmlessly toward `ujust setup-kali` if the container
hasn't been created yet, rather than letting `distrobox enter` fall through to its
default behavior (prompting to create a host-default Fedora box).

### `kalicli` helpers (rootless Quadlet)

- `kalicli <cmd>` — run `<cmd>` in the rootless `spinofin-kalicli` container.
  No args drops you into an interactive login shell. Automatically starts the
  `spinofin-kalicli.service` on demand if stopped.
- `iskalicli` — report whether `kalicli` is built and running (exit 0 = present, 1 = not set up, 2 = no podman).

There is deliberately no `kaliclisudo`: `kalicli` is rootless (container UID 0 is mapped
to host UID), so you are already root inside the container with no host privileges.

## Layout

```
custom/aliases/
└── system_files/
    └── etc/
        ├── fish/
        │   └── conf.d/
        │       ├── spinofin-kali-aliases.fish      # Fish distrobox helpers
        │       └── spinofin-kalicli-aliases.fish   # Fish Quadlet helpers
        └── profile.d/
            ├── spinofin-kali-aliases.sh        # Bash/Zsh distrobox helpers
            └── spinofin-kalicli-aliases.sh     # Bash/Zsh Quadlet helpers
```

Wired into the image by `build/17-aliases.sh`, a straight `cp -a` copy --
mirrors `custom/branding/`'s mechanism exactly, just for a different
on-image path.
