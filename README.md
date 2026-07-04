# spinofin

<p align="center">
  <img src="docs/assets/spinofin-logo-full.svg" alt="spinofin — a declarable, image-based pentesting OS built on Bluefin" width="440">
</p>

> A declarable, image-based pentesting OS — built on Bluefin. Kali-grade under the hood, GNOME-clean on the surface.

## How to Get Started with spinofin

spinofin ships as a bootc/OCI image you rebase onto an existing [Bluefin](https://projectbluefin.io) install. Three steps: install Bluefin, switch to spinofin, then run the setup recipes.

### 1. Install Bluefin

spinofin is *assembled from* the Bluefin ecosystem and uses the full Bluefin image as its base, so a stock Bluefin install is the supported starting point. (`bootc switch` rebases an existing bootc system — Bluefin is one; a stock Fedora install is not.)

1. Download the current Bluefin ISO from <https://projectbluefin.io> (see the [installation guide](https://docs.projectbluefin.io/installation/) for variants and hardware notes).
2. Boot the ISO and install with whole-disk automatic partitioning (~20 minutes).
3. If you enable Secure Boot, enroll the Universal Blue key when prompted (password: `universalblue`).
4. Boot into Bluefin and finish first-time setup.

### 2. Switch to spinofin

From the booted Bluefin system, rebase onto the latest spinofin `:stable` image and reboot:

```bash
sudo bootc switch ghcr.io/zoeruda/spinofin:stable
sudo systemctl reboot
```

spinofin's `:stable` images (built from `main`) are signed with keyless cosign/OIDC via Fulcio; `:testing` images are intentionally left unsigned. To require a valid signature on each pull, add `--enforce-container-sigpolicy` to the `bootc switch` command. If you're forking this repo, see [Optional: Enable Image Signing](#optional-enable-image-signing) to set it up for your own registry.

### 3. Get set up (ujust recipes)

After rebooting into spinofin, install the tooling. None of this is baked into the image — it is pulled at runtime so the host stays Track-B-ready (see [No Build-Time Layering](#no-build-time-layering)).

Host-side CLI tools (Homebrew) and Python-only tools (pipx):

```bash
ujust install-default-apps    # host-side CLI tools from the default Brewfile
ujust install-pipx-tools      # Python-only tools (soaphound, bloodyAD, ...)
```

Heavy pentest tooling lives in a single shared, rootful Kali container. Provision it once, then pull tool families on demand:

```bash
ujust setup-kali              # build the shared Kali (kali-rolling) container
ujust setup-metasploit        # initialise the Metasploit database (msfdb) inside it
ujust setup-powerview         # install powerview.py inside the container via pipx
ujust setup-bloodhound        # install + provision BloodHound CE (databases)
ujust bloodhound-start        # start BloodHound CE (single 'get going' command)
ujust export-impacket         # expose impacket-* commands to the host shell
ujust link-wordlists          # expose the Kali wordlists to host-native tools
ujust toggle-nmap             # choose where nmap lives: container / host / both / none
ujust list-kali-toolsets      # list the available Kali tool families
ujust install-kali-web        # e.g. add the web-app testing family (see list for the rest)
ujust enter-kali              # drop into a shell in the container
```

GUI apps (Flatseal, Wireshark, Burp Suite Community, KeePassXC, Remmina) install automatically on first boot via Flatpak — no command needed.

## What Makes this Raptor Different?

**What this fork is for:** a declarable, verifiable pentesting OS with Kali Linux-like tooling on a GNOME desktop, built using lessons from Bluefin and [Dakota](https://github.com/projectbluefin/dakota) (Bluefin's GNOME OS bootc prototype). It uses no build-time package layering — see "No Build-Time Layering" below — so the base image can move from Fedora Atomic to a true GNOME OS bootc image later without first unwinding a pile of system packages.

This image is based on Bluefin (`ghcr.io/ublue-os/bluefin`, itself Fedora
Silverblue + GNOME + Bluefin's desktop config), aiming toward Kali Linux-like
pentesting functionality, built with no build-time package layering.

### No Build-Time Layering

This fork does not add packages via `dnf5`/`rpm-ostree`/COPR in its own
customizations (`build/*.sh`, `Containerfile`) — only `systemctl enable`/`mask`
service toggles on binaries the base image already ships. Everything else goes
through Homebrew or Flatpak instead:

- **Why**: the long-term target base is a true GNOME OS bootc image
  (`quay.io/gnome_infrastructure/gnome-build-meta`), which has no system
  package manager at all. Avoiding layering from the start means there's
  nothing to unwind later.
- **Enforced by**: `.github/workflows/no-layering-check.yml` fails any PR
  that introduces a `dnf5`/`yum`/`apt`/`rpm-ostree install` call in
  `build/*.sh` or `Containerfile`.
- **Where tools actually go**: CLI tools → `custom/brew/*.Brewfile`
  (installed at runtime via `ujust install-default-apps`); GUI apps →
  `custom/flatpaks/*.preinstall` (installed on first boot).

### Added Applications (Runtime)

- **CLI Tools (Homebrew)**: host-side recon/web tooling, all staged into the image at `/usr/share/ublue-os/homebrew/default.Brewfile` and installed at runtime via `ujust install-default-apps` (consistent with the no-layering policy — brew installs live in the user's writable layer, not the image):
  - **Subdomain / DNS / ASN recon:** `subfinder`, `amass`, `dnsx`, `shuffledns` (+ `massdns` as its resolver engine), `mapcidr`, `asnmap`, `cdncheck`, `uncover`.
  - **HTTP probing & crawling:** `httpx` (ProjectDiscovery's probe — not the Python `httpx` library; see the collision note in the Brewfile), `katana`, `gau`, `tlsx`.
  - **Web fuzzing / content discovery:** `ffuf`, `feroxbuster`, `gobuster`.
  - **Web vuln / app testing:** `nuclei` (template scanner), `nikto`, `dalfox`.
  - **Secret discovery:** `trufflehog`, `gitleaks`.
  - **TLS inspection:** `sslscan` (cipher enumeration), `testssl` (comprehensive protocol/cert/vuln analysis — human-readable engagement reports).
  - **Traffic interception:** `proxify` (ProjectDiscovery HTTP/HTTPS proxy — route any CLI tool's traffic through Burp without proxy-aware client support; complements `proxychains-ng` which works at the syscall level).
  - **Password cracking (offline, CPU/GPU, unprivileged):** `john-jumbo`, `hashcat`.
  - **Online login attacks (connect-based, unprivileged):** `hydra`, `ncrack`.
  - **Port scanning:** `rustscan` (async connect-scan port finder). **Important:** rustscan's default behaviour auto-execs `nmap` after the port sweep; since `nmap` lives only in the container now, use `rustscan -a <target> --scripts none` to get ports only, then hand off to the container's nmap via `kali nmap -sV -sC -p <ports> <target>`.
  - **Exploit reference:** `exploitdb` (`searchsploit`).
  - **Pivoting / proxying:** `proxychains-ng`, `chisel-tunnel` (installs the `chisel` binary — fast TCP/UDP tunnel over HTTP for port-forwarding through a foothold).
  - **Networking utilities:** `netcat`, `rlwrap` (readline wrapper for tools lacking line-editing, e.g. raw `nc` shells).

  Which tools go host-side (here) vs. into the Kali container is governed by the **host-vs-container rubric** documented at the top of [`custom/brew/default.Brewfile`](custom/brew/default.Brewfile). Raw-socket / privileged / Kali-only / heavy-dependency tools (e.g. `masscan`, `naabu`, `nmap`) stay in the container; Python-only tools without a clean formula go in the `pipx` bucket below. `pipx` itself is installed via this Brewfile to bootstrap that bucket.
- **CLI Tools (pipx)**: Python-only tools with no clean Homebrew formula, declared in [`custom/pipx/default.pipx`](custom/pipx/default.pipx) and installed at runtime via `ujust install-pipx-tools` into the user's isolated pipx venvs (same no-layering posture as brew):
  - `bloodyAD` — Active Directory privesc framework (pure-Python wheel, no system build deps).
  - `soaphound` — BloodHound ingestor over ADWS/SOAP (the Python tool, not the .NET one). Pure-Python; its only real dependency, `impacket`, installs from prebuilt manylinux wheels and pulls no `gssapi`, so no system build headers are needed. That bundled `impacket` is isolated inside soaphound's own pipx venv and is **not** on `$PATH` — the standalone `impacket-*` CLI scripts come from the **container** instead (see below), so there's no host/container collision.
  - `bloodhound-ce` — provides the `bloodhound-ce-python` ingestor for **BloodHound CE** (not legacy `bloodhound-python`). Same lineage as impacket and the same shape as `soaphound`: a `py3-none-any` wheel whose dependencies (dnspython, impacket, ldap3, pyasn1, pycryptodome) are pure-Python or ship prebuilt manylinux wheels — no `gssapi`, no build headers.
  - `wafw00f` — web application firewall fingerprinting (pure-Python; not in homebrew-core).
  - `arjun` — HTTP parameter discovery (has a brew formula but no Linux bottle, so it lands here).
  - `certipy-ad` — AD Certificate Services enumeration and exploitation (ESC1–ESC16 attack paths). Pure-Python `py3-none-any` wheel; all deps ship prebuilt manylinux wheels.
  - `sslyze` — deep TLS/SSL server analysis: ciphers, protocols, certificates, and known attack vulns (Heartbleed, ROBOT, CRIME, etc.) with structured JSON output. Its C extension (`nassl`) ships prebuilt `manylinux2014_x86_64` wheels for Python 3.10+, so no build headers are needed on the host.
  - `ldapdomaindump` — Active Directory LDAP dump: enumerates users, groups, computers, policies, and trusts and writes HTML/JSON/grep-friendly output. Quick first-look at an AD environment without standing up Neo4j. Pure-Python deps, no build headers.
  - Routed to the Kali container instead (documented in the list file): `powerview.py` (needs both `libkrb5-dev` and `python3-dev` build headers — `gssapi` ships no Linux manylinux wheels and always builds from source, requiring krb5 headers *and* `Python.h`; install with `ujust setup-powerview`) and `wfuzz` (only a stale Python-2 brew tap exists; now baked into the container via apt).
- **Container tool families (Kali metapackages)**: pulled on demand into the shared rootful Kali container via the recipes in [`custom/ujust/kali-toolsets.just`](custom/ujust/kali-toolsets.just) (container-local `apt`, never host layering). `ujust list-kali-toolsets` lists them; e.g. `ujust install-kali-web`, `-passwords`, `-information-gathering`, `-exploitation`. Hardware families (wireless, bluetooth, rfid, sdr) are intentionally omitted pending host device passthrough.
- **Container-baked tooling, wordlists & databases**: declared in [`custom/distrobox/spinofin-kali.ini`](custom/distrobox/spinofin-kali.ini) and managed by recipes in [`custom/ujust/kali-container.just`](custom/ujust/kali-container.just). Baked into the container at assemble time:
  - `metasploit-framework` + `postgresql` — core framework and its database backend.
  - `impacket-scripts` — `/usr/bin/impacket-*` wrappers; exported to the host via `ujust export-impacket`.
  - `vim` + `nano` — editor baseline.
  - `fastfetch` — system-info banner on container entry.
  - `nmap` — runs with full `CAP_NET_RAW` in the rootful container: raw-socket SYN scans (`-sS`), OS detection (`-O`), and the NSE script engine (`--script`). This is the primary reason `nmap` lives here rather than host-side; the host has no privileged networking capability. Access it as `kali nmap …` or from inside `ujust enter-kali`.
  - `git` — ad-hoc tool installs and PoC clones inside the container.
  - `tcpdump` — packet capture via `CAP_NET_RAW`.
  - `netcat-openbsd` — classic `nc` for reverse shells, port testing, file transfer.
  - `libkrb5-dev` + `python3-dev` + `pipx` — build dependencies and installer for `powerview.py` (`gssapi` ships no Linux manylinux wheels and always builds from source, needing both the krb5 headers and `Python.h` to compile its C extension; all apt-legal in the container).
  - `netexec` (`nxc`) — SMB / LDAP / WinRM / RDP / SSH / MSSQL lateral movement and enumeration; the actively maintained CrackMapExec successor.
  - `enum4linux-ng` — next-gen SMB/Samba/AD enumeration with JSON/YAML output.
  - `sqlmap` — automated SQL injection and database takeover.
  - `wfuzz` — web application fuzzer (forms, headers, parameters, directories); only a stale Python-2 brew tap exists upstream so the Kali apt build is the clean home.
  - `seclists` + `wordlists` — Kali wordlist trees at the canonical `/usr/share/seclists` and `/usr/share/wordlists` (`seclists` is ~1 GB+, so the assemble is heavier by design).
  - `systemd` + `libpam-systemd` — required because the container runs as an init container (`init=true` in the `.ini`) so that systemd-managed services (BloodHound CE, PostgreSQL) work as they do on stock Kali.

  Setup/launch recipes:
  - `ujust setup-metasploit` — initialise the Metasploit `msfdb` database.
  - `ujust setup-powerview` — install [powerview.py](https://github.com/aniqfakhrul/powerview.py) inside the container via a container-local `pipx` install isolated to `/opt/spinofin/pipx` (NOT `~/.local/bin`, which is shared with the host's own brew-managed pipx — see the recipe comments for why). Requires `libkrb5-dev` + `python3-dev` headers baked into the container; `gssapi` ships no Linux manylinux wheels so host-side pipx cannot install this. Idempotent — safe to re-run. The installed console script is `powerview` (the repo is named `powerview.py`, the command is not). Use `kali powerview --help` or enter the container to run it.
  - `ujust setup-bloodhound` → `ujust bloodhound-start` — install BloodHound CE on demand, provision its PostgreSQL + neo4j databases, then start it. You only need `setup-bloodhound` **once**; after every later reboot, `bloodhound-start` alone re-runs that same proven bring-up sequence (cheap, no apt, fully offline) and starts the service — no need to repeat `setup-bloodhound`. BloodHound is managed by a systemd unit, so the container runs as an **init container** (`init=true` in the `.ini`); if a command errors with *"System has not been booted with systemd as init system"*, the container predates that and needs `ujust rebuild-kali`. **Headless handling:** Kali's helpers try to pop a local browser (`xdg-open`), which has no display in the container — so both recipes neutralize that step (provisioning still completes; you open **`http://localhost:7474`** in your *host* browser the first time to set the neo4j password and update `/etc/bhapi/bhapi.json`), and `bloodhound-start` starts the stack **non-blocking** instead of running Kali's wait-for-API-then-`xdg-open` wrapper (which hangs headless). Open the UI at **`http://localhost:8080`** in your host browser. **Note on neo4j:** Kali's bloodhound package manages neo4j directly via its own binary, not as a `neo4j.service` systemd unit — so a warning mentioning `neo4j.service` (e.g. *"Unit ... not found"*) is expected and safe to ignore; the bring-up step already starts/verifies neo4j the correct (non-systemd) way.
  - `ujust export-impacket` — surface the container's `impacket-*` scripts to the host shell as distrobox wrappers in `~/.local/bin`, so `impacket-secretsdump` (etc.) run from the host but execute in the container.
  - `ujust link-wordlists` — stage the Kali wordlists for **host-native** tools (john, hashcat, ffuf). distrobox shares only `$HOME` (not the container's `/usr`), *and* `/usr/share/wordlists` is mostly symlinks into other packages (many dangling), so a bare symlink/copy would be broken on the host. Instead this stages **real files** under `~/.local/share/spinofin/wordlists` (linked as `~/wordlists`): it relocates the `seclists` tree there (symlinking `/usr/share/seclists` back so the container keeps its path) and decompresses `rockyou` to `~/wordlists/rockyou.txt`. Use e.g. `hashcat -m 0 -a 0 hashes.txt ~/wordlists/rockyou.txt` or `john --wordlist=~/wordlists/rockyou.txt hashes.txt`, plus the real lists under `~/wordlists/seclists/Passwords/`.
  - `ujust toggle-nmap` — interactively pick where `nmap` is installed: **both** (default — brew's `rustscan` formula pulls in host `nmap` as a real dependency anyway, so this is the natural resting state: unprivileged `-sT` connect scans via brew on the host, full raw-socket scans via `CAP_NET_RAW` in the container, run with the `kali` alias), **container-only** (recommended if you want full scan capability without a duplicate host copy), **host-only** (unprivileged `-sT` only, no raw sockets — recommended for `rustscan` integration), or **none**. Manages the *live* state on each side (`brew install`/`uninstall --ignore-dependencies`, container `apt install`/`remove`) — it does not edit either source of truth, so re-provisioning from either one brings its copy of `nmap` back regardless of your last choice: `ujust install-default-apps`/`install-all-brew` for host `nmap` (those recipes now detect and repair formulas with missing dependencies via `brew missing` + `brew reinstall`, so a plain re-run pulls it back in), and `ujust rebuild-kali` for container `nmap` (still declared in `spinofin-kali.ini`; `setup-kali` never touches an existing container, so only a rebuild brings it back). Re-run `toggle-nmap` afterward if you want a different state.
- **Host-shell aliases for the container** (baked into the image, no setup step): `kali` and `kalisudo`, declared in [`custom/aliases/`](custom/aliases/README.md) and shipped the same way as `custom/branding/` — a plain `/etc/profile.d/*.sh` file overlay (not a package), live as soon as you boot the image.
  - `kali <cmd>` — run `<cmd>` in the `spinofin-kali` container as your user. No args drops you into an interactive shell (same as `ujust enter-kali`).
  - `kalisudo <cmd>` — same, but as root in the container; this is the shorthand for `distrobox enter --root spinofin-kali -- sudo <cmd>`.
  - **Existence guard:** before calling `distrobox enter`, both check the container actually exists. Plain `distrobox enter` on a non-existent container name does **not** fail cleanly — by default it interactively offers to create a new container under that name using the *host's* default image (Fedora) instead, which is exactly the wrong thing here. If `spinofin-kali` hasn't been created yet, you get a clear message pointing at `ujust setup-kali` instead of that prompt.
  - Targets `bash` (Bluefin's default interactive shell) via Fedora's `/etc/bashrc` → `/etc/profile.d` convention, which covers both login and ordinary new-terminal sessions. zsh users will need to `source /etc/profile.d/spinofin-kali-aliases.sh` from their own `~/.zshrc`.
- **Sudo prompt disambiguation** (baked into the image + set up by `ujust setup-kali`): a sudo password prompt is ambiguous about whether it wants the host's or the container's password by default. Declared in [`custom/sudo-prompt/`](custom/sudo-prompt/README.md) (host side, shipped the same way as `custom/aliases/`) and in `setup-kali` itself (container side). Both set `Defaults passprompt="[sudo] password for %p (on %h): "` — the same line, resolving differently because `%h` (sudo's hostname escape) differs by context: the container's hostname is explicitly pinned to `spinofin-kali` via `hostname=` in the `.ini`, so you always see e.g. `[sudo] password for zoe (on spinofin-kali):` inside the box vs. `...(on <real-hostname>):` on the host. This only ever *adds* a file under `/etc/sudoers.d/` — it never edits the main `/etc/sudoers`, so a mistake here degrades gracefully (sudo just skips that one file) rather than locking out sudo entirely.
- **GUI Apps (Flatpak)**: preinstalled on first boot from Flathub (all IDs validated by `validate-flatpaks.yml`):
  - `com.github.tchx84.Flatseal` — Flatpak permission manager. The original preinstall sanity-check (the Bluefin base does not already ship it), and useful for managing the permissions of the sandboxed security GUIs below.
  - `org.wireshark.Wireshark` — protocol analyzer. **Note:** the Flathub build is sandboxed and **cannot do live capture** — it opens/analyzes existing `.pcap`/`.pcapng` files. For promiscuous-mode / live capture, the move is to install Wireshark **inside the Kali container** via apt and run it as root from there (`distrobox enter --root spinofin-kali -- sudo wireshark`); the rootful container has the `CAP_NET_RAW` capture needs. Host-side `dumpcap` privileges remain the roadmap's known-hard, deferred item.
  - `net.portswigger.BurpSuite-Community` — Burp Suite Community Edition (web proxy / app-testing). **Note:** this is a community-maintained Flathub *wrapper* of the proprietary Burp Community build — it is not verified by or affiliated with PortSwigger.
  - `net.giuspen.cherrytree` — Cherrytree, hierarchical note-taking for structured engagement notes. (Current Flathub ID is `net.giuspen.cherrytree`; the older `com.giuspen.cherrytree` is superseded.)
  - `md.obsidian.Obsidian` — Obsidian, Markdown knowledge base for notes/reporting. Verified by the Obsidian team on Flathub; proprietary EULA, ~600 MiB.
  - `org.keepassxc.KeePassXC` — local password manager for storing credentials found during an engagement (cracked hashes, service accounts, reused passwords). Published on Flathub by the KeePassXC team. No cloud sync; supports TOTP and SSH agent integration.
  - `org.remmina.Remmina` — RDP / VNC / SSH / X2Go GUI client, essential for accessing compromised Windows hosts over RDP or pivoting to internal Linux machines. GTK-based (fits the GNOME desktop). **Note:** Flatpak sandboxing may restrict SSH key access from `~/.ssh` — grant filesystem access via Flatseal if needed.

### Removed/Disabled

- Nothing removed from the base image yet

### Configuration Changes

- No-layering policy as mentioned above
- Custom Branding: Spinosaurus sail logo and spinofin wordmark to replace Bluefin's branding

_Last updated: 2026-06-30_

> Replace the placeholders above with your actual customizations whenever you add or remove packages, apps, or configuration. This section is what tells users how your image differs from the base.

## Guided Copilot Mode

This template works best with **phased prompts** that let Copilot bootstrap your image in three stages.

### Phase 1 — Bootstrap

Use this prompt first to get your fork building:

```
Bootstrap a new custom OS from @projectbluefin/finpilot. Name it after this repository. Read `.agents/skills/finpilot-onboarding.md` first, then:
1. Rename `finpilot` in the 7 required files
2. Enable GitHub Actions and set RENOVATE_TOKEN (repo + workflow scopes)
3. Configure branch protection for `main` with `validate` as a required status check
4. Enable auto-merge
5. Trigger the first green build on `main`
6. Add the "What Makes this Raptor Different" section to README.md (with placeholders)
```

### Phase 2 — Customize

Once the first build is green, use this prompt to add packages:

```
Read `.agents/skills/finpilot-packages.md` and `.agents/skills/finpilot-custom.md`, then:
1. Add one system package to the image in `build/10-build.sh`
2. Add one CLI tool to `custom/brew/default.Brewfile`
3. Add one GUI app to `custom/flatpaks/default.preinstall`
4. Add shortcuts in `custom/ujust/custom-apps.just` to install them
5. Update the README "What Makes this Raptor Different" section with the new entries
6. Run `just build && just build-qcow2 && just run-vm-qcow2` to verify locally
7. Open a PR and merge once `validate` passes
```

### Phase 3 — Production

When you are ready for production, use this prompt to harden the setup:

```
Read `.agents/skills/finpilot-maintain.md` and `.agents/skills/finpilot-ci.md`, then:
1. Enable keyless image signing by uncommenting the step in `.github/workflows/build-image.yml`
2. Verify the cosign command works: cosign verify --certificate-identity-regexp="https://github.com/USER/REPO/.github/workflows/" --certificate-oidc-issuer="https://token.actions.githubusercontent.com" ghcr.io/USER/REPO:stable
3. Review the maintenance schedule in `finpilot-maintain.md`
```

## What's Included

### Build System

- Automated builds via GitHub Actions on every commit
- Self-hosted Renovate for automated dependency updates
- Automatic cleanup of old images (90+ days) to keep it tidy
- Pull request workflow - test changes before merging to main
  - PRs build and validate before merge
  - `main` branch builds `:stable` images
- Validates your files on pull requests so you never break a build:
  - Brewfile, Justfile, ShellCheck, Renovate config, pipx tool lists (checks each tool exists on PyPI / as a reachable git repo), and it'll even check to make sure the flatpak you add exists on FlatHub
  - Kali container packages: every `additional_packages` entry in `custom/distrobox/*.ini` and every `kali-tools-*` metapackage referenced in `custom/ujust/kali-toolsets.just` is checked against the real Kali apt repositories (`apt-cache show`, metadata only, nothing installed) — this is what would have caught the `python3-pipx` typo before merge, instead of `ujust setup-kali` failing with an undescriptive exit 1
- Production Grade Features
  - Container signing with keyless OIDC
  - See checklist below to enable these as they take some manual configuration

### Homebrew Integration

- Pre-configured Brewfiles for easy package installation and customization
- Includes curated collections: development tools, fonts, CLI utilities. Go nuts.
- Users install packages at runtime with `brew bundle`, aliased to premade `ujust commands`
- See [custom/brew/README.md](custom/brew/README.md) for details

### Flatpak Support

- Ship your favorite flatpaks
- Automatically installed on first boot after user setup
- See [custom/flatpaks/README.md](custom/flatpaks/README.md) for details

### ujust Commands

- User-friendly command shortcuts via `ujust`
- Pre-configured examples for app installation and system maintenance for you to customize
- See [custom/ujust/README.md](custom/ujust/README.md) for details

### Build Scripts

- Modular numbered scripts (10-, 20-, 30-) run in order
- Example scripts included for third-party repositories and desktop replacement
- Helper functions for safe COPR usage
- See [build/README.md](build/README.md) for details

## Quick Start

### 1. Create Your Repository

Click "Use this template" to create a new repository from this template.

### 2. Rename the Project

Important: Change `finpilot` to your repository name in these 7 files:

1. `Containerfile` (`# Name:` comment and `ARG IMAGE_NAME`): `# Name: your-repo-name`
2. `Justfile` (`export IMAGE_NAME := env("IMAGE_NAME", ...)`): `your-repo-name`
3. `README.md` (title): `# your-repo-name`
4. `artifacthub-repo.yml` (`repositoryID`): `repositoryID: your-repo-name`
5. `custom/ujust/README.md` (bootc switch example): `localhost/your-repo-name:stable`
6. `.github/workflows/clean.yml` (`packages`): `packages: your-repo-name`
7. `iso/iso.toml` (bootc switch URL): `ghcr.io/YOUR_USERNAME/your-repo-name:stable`

### 3. Enable GitHub Actions

- Go to the "Actions" tab in your repository
- Click "I understand my workflows, go ahead and enable them"

Your first build will start automatically!

Note: spinofin's `:stable` (main) images are signed with keyless cosign/OIDC — no signing keys or secrets to manage. `:testing` images are left unsigned by design. Forks inherit this enabled workflow; see "Optional: Enable Image Signing" below for how it works.

### 4. Enable Renovate (Required)

Renovate automatically updates dependencies and GitHub Actions (including workflow files). This template uses a self-hosted Renovate runner via `projectbluefin/actions`.

**One-time setup:**

1. Go to GitHub → Settings → Developer settings → **Personal access tokens** → **Tokens (classic)**
2. Click **Generate new token (classic)**
3. Set a note like `renovate-spinofin`
4. Select scopes: **`repo`** (full control) and **`workflow`** (update workflows)
5. Click **Generate token** and copy the value
6. Go to your repository → Settings → Secrets and variables → Actions
7. Add a new secret: **`RENOVATE_TOKEN`** (paste the token value)
8. Enable **Settings → General → Pull Requests → Allow auto-merge** so Renovate can merge low-risk updates after checks pass
9. **Configure branch protection for `main`** (required for automerge to work):
   - Go to Settings → Branches → Add rule
   - Set **Branch name pattern** to `main`
   - Enable **"Require a pull request before merging"**
   - Enable **"Require status checks to pass before merging"**
   - Add `validate` as a required status check
   - Enable **"Require branches to be up to date before merging"** (recommended)

Renovate will run every 6 hours and on config changes. It pins GitHub Actions to SHAs and updates tracked image digests automatically.

### 5. Customize Your Image

Choose your base image in `Containerfile` (the `FROM` line):

```dockerfile
FROM ghcr.io/ublue-os/bluefin:stable
```

This fork uses the full Bluefin image as its base (for its GNOME desktop
defaults, fastfetch, fonts, and codecs out of the box). Note that finpilot's
`ctx` stage still copies `@projectbluefin/common` and `@ublue-os/brew` into
the image, which full Bluefin already contains — this redundancy is currently
accepted (we'll override desktop config with Kali-like settings in a later
phase) and is a cleanup candidate once the `build/*.sh` scripts no longer
depend on those `/oci/...` paths.

Add your packages — this fork has a strict no-layering policy (see "No
Build-Time Layering" above), so packages are not added via `dnf5` in
`build/10-build.sh`. Instead:

- Add Brewfiles in `custom/brew/` ([guide](custom/brew/README.md))
- Add Flatpaks in `custom/flatpaks/` ([guide](custom/flatpaks/README.md))
- Add ujust commands in `custom/ujust/` ([guide](custom/ujust/README.md))
- Add baked-in shell aliases/functions in `custom/aliases/` ([guide](custom/aliases/README.md)) — a plain `/etc/profile.d/*.sh` file overlay, the same file-overlay mechanism `custom/branding/` uses, not a package install. spinofin ships `kali`/`kalisudo` this way (see below) as the working example.
- Add baked-in sudo-prompt or other `/etc/sudoers.d/` customizations in `custom/sudo-prompt/` ([guide](custom/sudo-prompt/README.md)) — same file-overlay mechanism; only ever *adds* a new file, never edits the main `/etc/sudoers`.

### 6. Development Workflow

All changes should be made via pull requests:

1. Open a pull request on GitHub with the change you want.
2. The PR will automatically trigger:
   - Build validation
   - Brewfile, Flatpak, Justfile, pipx, and shellcheck validation
   - Test image build
3. Once checks pass, merge the PR
4. Merging triggers publishes a `:stable` image

### 7. Deploy Your Image

Switch to your image:

```bash
sudo bootc switch ghcr.io/zoeruda/spinofin:stable
sudo systemctl reboot
```

## Optional: Enable Image Signing

**spinofin already has signing enabled** for `:stable` (main) images — see the "Sign and publish" step in `.github/workflows/build-image.yml`, gated to the `main` branch so `:testing` stays unsigned. The steps below explain how it works and are what you'd adjust if you fork this repo for your own registry. Signing is strongly recommended for production use.

### Why Sign Images?

- Verify image authenticity and integrity
- Prevent tampering and supply chain attacks
- Required for some enterprise/security-focused deployments
- Industry best practice for production images

### Setup Instructions

This template uses **keyless OIDC signing** via Cosign and GitHub Actions. No manual key generation, `cosign.key`, or `cosign.pub` files are required.

1. Edit `.github/workflows/build-image.yml`
2. Find the "OPTIONAL: Sign and attest" section
3. Uncomment the `Sign and publish` step (remove the `#` from the beginning of each line in that section)
4. Commit and push

Your next build will produce a signed image. The signature is created using GitHub's OIDC token via Fulcio.

Users can verify your images with:

```bash
cosign verify \
  --certificate-identity-regexp="https://github.com/zoeruda/spinofin/.github/workflows/" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  ghcr.io/zoeruda/spinofin:stable
```

## Love Your Image? Let's Go to Production

Ready to take your custom OS to production? Enable these features for enhanced security, reliability, and performance:

### Production Checklist

- [x] **Enable Image Signing** (Recommended)
  - Provides cryptographic verification of your images
  - Prevents tampering and ensures authenticity
  - Uses keyless OIDC signing via GitHub Actions — no keys or secrets required
  - See "Optional: Enable Image Signing" section above for setup instructions
  - Status: **Enabled** — `:stable` (main) images are signed; `:testing` is intentionally left unsigned

- [ ] **Enable Image Rechunking** (Recommended)
  - Optimizes bootc image layers for better update performance
  - Reduces update sizes by 5-10x when combined with package cadence data
  - Improves download resumability with evenly sized layers
  - To enable:
    1. Edit `.github/workflows/build-image.yml`
    2. Find the "OPTIONAL: Rechunking" section
    3. Uncomment the `bootc-build/chunka` step
  - For optimal results, also add `bootc-build/apply-pkg-intervals` and a `pkg-cadence.yml` workflow
  - Status: **Not enabled by default** (optional optimization)

#### Adding Image Rechunking

After building your bootc image, add a rechunk step before pushing to the registry. The template ships with a commented `bootc-build/chunka` step in `.github/workflows/build-image.yml`:

```yaml
- name: Rechunk image
  if: github.event_name != 'pull_request'
  id: rechunk-image
  uses: projectbluefin/actions/bootc-build/chunka@6231015b336556d2ff0adc1d1e59514bf19dcb42 # v1
  with:
    source-image: localhost/${{ env.IMAGE_NAME }}:${{ env.DEFAULT_TAG }}
    max-layers: 128
```

This uses [chunkah](https://github.com/coreos/chunkah) to reorganize OCI layers without rpm-ostree. Renovate will keep the action updated once it is uncommented.

**Parameters:**

- `max-layers`: Maximum number of layers for the rechunked image (128 is a typical bootc default)
- `source-image`: Local image reference to rechunk

**For optimal OTA deltas**, also add `bootc-build/apply-pkg-intervals` before the rechunk step and create a `.github/workflows/pkg-cadence.yml` workflow that calls `projectbluefin/actions/.github/workflows/reusable-pkg-cadence.yml@v1`. This groups packages by update cadence (weekly, monthly, quarterly, yearly) so a typical update only downloads layers that actually changed. Without it, chunkah still works but uses default layer grouping.

**References:**

- [CoreOS rpm-ostree build-chunked-oci documentation](https://coreos.github.io/rpm-ostree/build-chunked-oci/)
- [bootc documentation](https://containers.github.io/bootc/)

### After Enabling Production Features

Your workflow will:

- Sign all images using keyless OIDC signing
- Provide cryptographic proof of authenticity via SLSA build provenance attestation

Users can verify your images with:

```bash
cosign verify \
  --certificate-identity-regexp="https://github.com/zoeruda/spinofin/.github/workflows/" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  ghcr.io/zoeruda/spinofin:stable
```

## Detailed Guides

- [Homebrew/Brewfiles](custom/brew/README.md) - Runtime package management
- [Flatpak Preinstall](custom/flatpaks/README.md) - GUI application setup
- [ujust Commands](custom/ujust/README.md) - User convenience commands
- [Build Scripts](build/README.md) - Build-time customization

## finpilot

spinofin is built on [finpilot](https://github.com/projectbluefin/finpilot), Bluefin's template for assembling your own custom bootc image. The generic template description follows.

A template for building custom bootc operating system images based on the lessons from [Universal Blue](https://universal-blue.org/) and [Bluefin](https://projectbluefin.io). It is designed to be used manually, but is optimized to be bootstraped by GitHub Copilot. After set up you'll have your own custom Linux.

This template uses the **multi-stage build architecture** from @projectbluefin/distroless, combining resources from multiple OCI containers for modularity and maintainability. See the [Architecture](#architecture) section below for details.

**Unlike previous templates, you are not modifying Bluefin and making changes.**: You are assembling your own Bluefin in the same exact way that Bluefin, Aurora, and Bluefin LTS are built. This is way more flexible and better for everyone since the image-agnostic and desktop things we love about Bluefin lives in @projectbluefin/common.

Instead, you create your own OS repository based on this template, allowing full customization while leveraging Bluefin's robust build system and shared components.

> Be the one who moves, not the one who is moved.

## Architecture

This template follows the **multi-stage build architecture** from @projectbluefin/distroless, as documented in the [Bluefin Contributing Guide](https://docs.projectbluefin.io/contributing/).

### Multi-Stage Build Pattern

**Stage 1: Context (ctx)** - Combines resources from multiple sources:

- Local build scripts (`/build`)
- Local custom files (`/custom`)
- **@projectbluefin/common** - Desktop configuration shared with Aurora (includes branding/artwork content)
- **@ublue-os/brew** - Homebrew integration

**Stage 2: Base Image** - Default options:

- `quay.io/fedora-ostree-desktops/silverblue:44` (Fedora-based GNOME desktop, default)
- `quay.io/centos-bootc/centos-bootc:stream10` (CentOS-based alternative)

### Benefits of This Architecture

- **Modularity**: Compose your image from reusable OCI containers
- **Maintainability**: Update shared components independently
- **Reproducibility**: Renovate automatically updates OCI tags to SHA digests
- **Consistency**: Share components across Bluefin, Aurora, and custom images

### OCI Container Resources

The template imports files from these OCI containers at build time:

```dockerfile
COPY --from=ghcr.io/projectbluefin/common:latest /system_files /oci/common
COPY --from=ghcr.io/ublue-os/brew:latest /system_files /oci/brew
```

Your build scripts can access these files at:

- `/ctx/oci/common/` - Shared desktop configuration (branding/artwork content lives inside `common`)
- `/ctx/oci/brew/` - Homebrew integration files

**Note**: Renovate automatically updates `:latest` tags to SHA digests for reproducible builds.

## Local Testing

Test your changes before pushing:

```bash
just build              # Build container image
just build-qcow2        # Build VM disk image
just run-vm-qcow2       # Test in browser-based VM
```

## Community

- [Universal Blue Discord](https://discord.gg/WEu6BdFEtp)
- [bootc Discussion](https://github.com/bootc-dev/bootc/discussions)

## Learn More

- [Universal Blue Documentation](https://universal-blue.org/)
- [bootc Documentation](https://containers.github.io/bootc/)
- [Video Tutorial by TesterTech](https://www.youtube.com/watch?v=IxBl11Zmq5wE)

## Security

This template provides security features for production use:

- Optional image signing with keyless OIDC cosign for cryptographic verification
- Automated security updates via Renovate
- Build provenance tracking

Image signing is enabled for `:stable` (main) images; the other features listed are opt-in. When you're ready to enable the rest, see the "Love Your Image? Let's Go to Production" section above.

## Troubleshooting

### Flatpaks not preinstalled after bootc switch

Flatpaks are installed on first boot via `flatpak-preinstall.service`, not during `bootc switch`. Ensure:

- Internet is available on first boot
- `flatpak-preinstall.service` completes (`systemctl status flatpak-preinstall.service`)
- Wait until the service finishes before checking for flatpaks

### Homebrew not installed after bootc switch

Homebrew is installed at build time into the image. If you don't see `brew`, verify your Containerfile includes the Brew integration. Check `custom/brew/README.md` for setup instructions.
