# custom/quadlet

Declaration for the **`kalicli`** container: a rootless, declaratively-built
podman box for CLI tools that don't need root or raw sockets.

## Files (the whole definition)

- `Containerfile` — the complete tool set. Built at runtime by
  `ujust setup-kalicli` into an immutable `localhost/spinofin-kalicli` image. This is the
  package source of truth; there is no separate package list and no imperative
  apt step.
- `spinofin-kalicli.container` — the runtime, as a podman [Quadlet][quadlet] unit
  (image, the single `/work` volume, hostname). Shipped in the image to
  `/etc/containers/systemd/users/` and generated into `spinofin-kalicli.service` by
  systemd.

`build/10-build.sh` copies the `Containerfile` to `/usr/share/spinofin/quadlet/`
(data for the runtime build) and installs the Quadlet to
`/etc/containers/systemd/users/`. Both are file copies — nothing is layered into
the host image, so the no-layering policy is untouched (that guard scans
`build/*.sh` and the root `Containerfile`, not this directory).

## Why a second container

`spinofin-kali` is a rootful distrobox: container-root is real host root, and
distrobox mounts the host's `/` at `/run/host` plus your `$HOME`. That's needed
for `CAP_NET_RAW` (nmap SYN scans, tcpdump) and exported wrappers, but it means
the container is not an isolation boundary.

`kalicli` is the opposite trade: rootless (podman maps container UID 0 to your
own host UID, so `root` inside has no host authority — hence no `kaliclisudo`),
no `/run/host`, no `$HOME` mount, no exported binaries. The only shared path is
`~/spinofin/work`, mounted at `/work`. Prefer it for anything that doesn't need
root or raw sockets, and especially for running untrusted code. See
[SECURITY.md](../../SECURITY.md) for the full comparison and honest limits.

## Fully declarative

The container is reproducible from the two files above and nothing else. There's
the declared toolset lives in an immutable image, so the durable way to add a
tool is "edit the Containerfile, rebuild." Two update paths, deliberately
different: `upgrade-kalicli` runs an in-place `apt full-upgrade` inside the
running container and **keeps** anything you added (fast, non-destructive, may
drift from the Containerfile); `rebuild-kalicli` rebuilds from the Containerfile
from scratch behind a confirmation, discarding in-container changes and
reconciling back to the declared toolset.

## Adding a tool

Add the package to the `install` list in `Containerfile`, then:

```bash
ujust rebuild-kalicli
```

`.github/workflows/validate-kalicli-image.yml` **builds** this Containerfile on
every PR that touches `custom/quadlet/`, so a wrong or conflicting package name
fails the install (a stronger check than name-existence), and it dry-runs the
Quadlet generator so a bad unit key fails too.

## Recipes & aliases

`custom/ujust/kalicli-container.just`: `setup-kalicli`, `upgrade-kalicli`,
`rebuild-kalicli`, `remove-kalicli`, and read-only `kalicli-status`.
Deliberately no per-tool setup recipes — everything is in the `Containerfile`.

Shell helpers (baked in, no setup): `kalicli [cmd]` and `iskalicli` (exit codes:
0 present, 1 not set up, 2 podman missing).

[quadlet]: https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html
