# pipx Integration

This directory declares Python-only CLI tools that are installed at **runtime**
via [pipx](https://pipx.pypa.io/) — the host-side bucket for Python apps that
don't have a clean Homebrew formula.

## How it works

1. **During build**: `*.pipx` files here are copied into the image at
   `/usr/share/spinofin/pipx/` (a plain file copy — nothing is installed on the
   host at build time, so this respects the no-layering policy).
2. **At runtime**: the user runs `ujust install-pipx-tools`, which reads the
   list and `pipx install`s each entry into its own isolated venv under
   `~/.local` (with a shim on `~/.local/bin`, already on Bluefin's PATH).

Installs therefore live in the user's writable layer, never in the image — the
same posture as the Homebrew bucket, and Track-B-friendly (pipx + `python3`
exist on the GNOME OS bootc base too).

## When a tool belongs here

A tool goes in `default.pipx` when **both** hold:

- it's a Python CLI app with no clean `homebrew-core` formula, **and**
- it installs with **no system build dependencies** — i.e. a pure
  `py3-none-any` wheel, or otherwise nothing needing apt/dnf `-devel` headers.

A Python tool that needs build headers (anything pulling `gssapi`, which needs
`libkrb5-dev`/`krb5-devel`, for example) **cannot** be installed host-side under
the no-layering policy and belongs in the Kali container instead, where the
build dependency is `apt`-installable container-locally.

## File format

One `pipx install` spec per line — a PyPI name, `name==version`, or a
`git+https://…` URL. Put comments on their **own** line (leading `#`); don't add
inline `#` comments after a spec, because git URLs can contain a
`#egg=`/`#subdirectory=` fragment.

## ujust recipes

- `ujust install-pipx-tools` — install everything declared in `default.pipx`
  (safe to re-run).
- `ujust upgrade-pipx-tools` — `pipx upgrade-all`.
- `ujust list-pipx-tools` — show what pipx currently manages.

See [`custom/ujust/pipx-tools.just`](../ujust/pipx-tools.just).
