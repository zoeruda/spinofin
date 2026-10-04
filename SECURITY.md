# Security policy

spinofin is a penetration-testing toolkit. Please read this before you rely on
it for anything that matters.

## Reporting a vulnerability

Report suspected vulnerabilities privately through GitHub's private
vulnerability reporting on <https://github.com/zoeruda/spinofin> (the **Security**
tab → *Report a vulnerability*). If that is unavailable, open a minimal issue
asking for a private contact channel rather than posting details publicly.
Please don't disclose publicly until a fix is available. This is a personal
project with no formal SLA, but reports will be acknowledged as soon as is
practical.

## What spinofin does and does not protect

spinofin's value is a **verifiable Bluefin GNOME base** plus convenient, largely
disposable pentest tooling. It is deliberately **not** a hardened, self-contained
appliance. Treat it as a convenient sandbox on top of a solid base — not as an
isolation boundary.

### The Kali container is rootful and shares your home

Heavy tooling lives in a single shared Kali distrobox container
(`custom/distrobox/spinofin-kali.ini`, managed by
`custom/ujust/kali-container.just`). By design that container is:

- **rootful** (`root=true`) — it runs from root's container storage and holds
  real host-kernel capabilities (`CAP_NET_RAW`, etc.) so raw-socket scans work;
- **root inside, with host reach** — the container is rootful; its `sudo` takes
  a password (distrobox has you set one on first `ujust enter-kali`), and once
  you have root it maps to real host root over the mounted host filesystem, so
  the password is a speed bump, not a boundary;
- **home- and network-sharing** — distrobox mounts your real `$HOME` and shares
  the host network so exported wrappers (`msfconsole`, `impacket-*`, …) can land
  in `~/.local/bin` and reach the network.

The consequence: the container protects the **host image's immutability**
(nothing is layered into the bootc image) — **not you**. A tool that escapes the
container, or a malicious proof-of-concept you clone and run inside it, has
straightforward reach to your real home directory, your SSH keys, and your host
network. Do not run untrusted code in this container expecting containment, and
do not point it at systems you are not authorized to test.

Practical guidance:

- **Prefer the `kalicli` container (below) for anything that doesn't need root
  or raw sockets.** Most CLI tooling doesn't.
- Prefer a throwaway machine or VM for engagements involving untrusted targets
  or untrusted tooling.
- Keep secrets (client data, credentials, SSH keys) off a box you also use as a
  pentest platform — or accept that the container can reach them.
- Rotate any default service credentials the tooling creates. In particular, set
  a real neo4j password immediately after `ujust setup-bloodhound` (it ships with
  the neo4j default of `neo4j`/`neo4j` until you change it, and the container
  shares host networking).

### `kalicli`: the safer container, and what it actually buys you

`ujust setup-kalicli` creates a second container that is **not** a distrobox.
It is plain rootless podman with no distrobox host integration:

- **rootless** — podman maps container UID 0 to your own host UID, so `root`
  inside `kalicli` is treated by the kernel as your unprivileged user. A process
  that escapes gains no host privilege. This is why there is no `kaliclisudo`;
  you are already root inside, and that root has no host authority.
- **no `/run/host`** — the host filesystem is not mounted.
- **no `$HOME` share** — your home directory, and therefore your SSH keys, are
  not reachable.
- **no exported binaries** — nothing is placed on your host `PATH`, so there is
  no wrapper-hijack surface.
- **one explicit seam** — `~/spinofin/work` is mounted at `/work`. That
  directory is the *only* host path the container can read or write.
- **immutable and declarative** — its tools come from
  `custom/quadlet/Containerfile` and its runtime from a podman Quadlet
  (`custom/quadlet/spinofin-kalicli.container`), both shipped in the image. `setup-kalicli`
  builds a local image and runs it as a `systemctl --user` service. The declared
  toolset is the Containerfile; `ujust upgrade-kalicli` applies in-place apt
  updates (which can drift from that declaration, but are kept), and `ujust
  rebuild-kalicli` reconciles back to it from scratch.

Prefer it for any tool that does not need root or raw sockets, and especially
for running untrusted code such as proof-of-concept exploits from the internet.

Honest limits:

- Anything you place in `~/spinofin/work` **is** reachable by the container.
  That is the seam; keep credentials and client data out of it.
- Rootless networking uses pasta/slirp4netns: no raw sockets (so no nmap SYN
  scans or tcpdump) and slower bulk transfers.
- Container isolation is not a security boundary of the same strength as a VM.
  A kernel-level container escape is still a kernel-level container escape. For
  genuinely hostile code, use a disposable VM.
- The base tracks `kali-rolling` via the Containerfile `FROM` (Renovate pins it
  to a digest). Rebuild to pick up base/tool updates.

### The tooling surface is not fully verified or pinned

The signed, immutable part of spinofin is the bootc **base image**. Most of the
actual tooling is pulled at runtime from mutable sources — Homebrew, pipx,
Flathub (including a community-maintained, unofficial Burp Suite wrapper), and a
rolling `kalilinux/kali-rolling` container. A couple of tools (`powerview.py`,
`kerbrute`) are commit-pinned; the rest are not, and the Kali container tracks
`:latest`. This is a reasonable trade-off for a rolling pentest toolkit, but it
means "verifiable" applies to the base image, not to the whole running system.

## Image signing status

`:stable` images are signed with keyless cosign/OIDC via Fulcio, and you can
verify a booted image with `ujust verify-image`.

**Signature verification is not enforced on the host.** As shipped, `bootc` will
pull and boot a `:stable` image without checking its signature — `ujust
verify-image` is a manual step you run after the fact.

This is a deliberate trade-off. spinofin signs keyless (OIDC/Fulcio), which keeps
CI key- and secret-free but **cannot** be enforced by the host's
`bootc`/`containers-policy.json` path: that path matches a fixed public key
(`keyPath`), and keyless GitHub Actions identities aren't matchable there.
Refusing an unsigned `:stable` at pull/upgrade time (the way Bluefin's
`--enforce-container-sigpolicy` path does) would require switching to fixed-key
cosign signing. spinofin currently keeps keyless by choice, so on-host
enforcement is not available. `:testing` images are intentionally unsigned.

If you want assurance about the image you're running, verify it explicitly:

```bash
ujust verify-image
```

To check the current stable image before updating to it:

```bash
ujust verify-image stable
```
