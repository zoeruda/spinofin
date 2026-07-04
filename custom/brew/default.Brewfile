# Default Brewfile for spinofin
# Uncomment packages you want to install, or add your own.
# Users install via: ujust install-default-apps
#
# ---------------------------------------------------------------------------
# HOST-vs-CONTAINER decision rubric (Phase 3)
# ---------------------------------------------------------------------------
# A tool belongs HERE (host-side, installed at runtime via brew) when ALL hold:
#   * It runs unprivileged from a normal shell -- no CAP_NET_RAW / raw sockets
#     / monitor mode / setuid needed for its primary use.
#   * It exists as a maintained homebrew-core formula with a Linux bottle.
#   * It is self-contained (Go/Rust/static-ish), not a Kali metapackage that
#     drags in a large apt-only dependency web.
#   * It is Track-B-friendly: brew behaves the same on the future GNOME OS
#     bootc base, so nothing here needs unwinding on rebase.
#
# A tool belongs in the KALI CONTAINER instead (apt inside
# custom/distrobox/spinofin-kali.ini, NOT here) when it needs raw-socket /
# privileged kernel access, is Kali-packaged-only, or pulls a heavy tree.
# Container-bound examples (do NOT add them here): masscan and naabu (SYN
# scans need CAP_NET_RAW), metasploit-framework (already there), and the
# privileged-capture tools flagged known-hard in the roadmap (Wireshark
# capture, aircrack monitor mode).
#
# Python-only tools with no good brew formula are a THIRD bucket: pipx
# (planned as the next Phase 3 unit), not brew and not necessarily the
# container.
# ---------------------------------------------------------------------------

# --- Bootstrap sanity check (Phase 1) --------------------------------------
# Proved the brew + ujust path end-to-end before any other tooling.
# nmap itself has since been moved to the Kali container exclusively (it needs
# CAP_NET_RAW for raw-socket SYN scans, -sS, and OS detection, -O; the rootful
# container provides that, an unprivileged host install can't). See
# custom/distrobox/spinofin-kali.ini.

# --- Host-side recon / web enumeration (Phase 3) ---------------------------
# All Go/Rust, unprivileged, verified present in homebrew-core (2026-06).
brew "subfinder"     # passive subdomain discovery (ProjectDiscovery)
brew "amass"         # OWASP attack-surface mapping / asset discovery
brew "httpx"         # fast HTTP probing toolkit (ProjectDiscovery).
                     # This is PD's httpx, NOT the Python httpx library --
                     # both ship an `httpx` binary, so do NOT `pipx install
                     # httpx` later or it will shadow this one on PATH.
brew "nuclei"        # template-based vulnerability scanner (ProjectDiscovery)
brew "ffuf"          # fast web fuzzer (Go)
brew "feroxbuster"   # recursive content discovery (Rust)
brew "gobuster"      # directory / DNS / vhost brute-forcing (Go)

# --- ProjectDiscovery recon suite (Phase 3) --------------------------------
# Companions to the subfinder/httpx/nuclei trio above. All Go, unprivileged,
# present in homebrew-core with x86_64 Linux bottles (verified 2026-06).
# API-key-driven sources (uncover) read keys from each tool's own config file,
# never from here.
brew "katana"        # headless/standard web crawler & spider
brew "dnsx"          # fast DNS resolver/toolkit (bulk A/AAAA/CNAME/etc.)
brew "mapcidr"       # CIDR/subnet expansion & aggregation helper
brew "asnmap"        # map org network ranges from an ASN / org / IP
brew "cdncheck"      # flag whether an IP/host sits behind a CDN/WAF/cloud
brew "tlsx"          # TLS grabber (SANs, issuers, expiry) for recon
brew "uncover"       # query Shodan/Censys/FOFA/etc. for exposed hosts (API keys)
brew "massdns"       # high-volume DNS stub resolver -- engine for shuffledns
brew "shuffledns"    # subdomain brute/resolve wrapper -- REQUIRES massdns above
                     # (it shells out to the massdns binary at runtime)

# --- Web application testing (Phase 3) -------------------------------------
brew "nikto"         # classic web-server misconfig / known-vuln scanner
brew "dalfox"        # XSS scanner & parameter analysis (Go)
brew "gau"           # getallurls: historical URLs (Wayback / OTX / CommonCrawl)

# --- Secret / credential discovery (Phase 3) -------------------------------
brew "trufflehog"    # find & verify leaked secrets in repos / files / CI
brew "gitleaks"      # audit git history for hardcoded secrets

# --- TLS/SSL inspection (Phase 3) ------------------------------------------
brew "sslscan"       # enumerate supported SSL/TLS ciphers & flaws
brew "testssl"       # comprehensive TLS/SSL server testing: ciphers, protocols,
                     # certificate chain, HSTS, known vulns (BEAST, POODLE,
                     # Heartbleed, etc.). Bash script wrapping OpenSSL -- no
                     # compiled binary, just bash + openssl. Complements sslscan
                     # (cipher enumeration) and the pipx sslyze (structured API
                     # output); testssl shines for human-readable engagement
                     # reports. Confirmed in homebrew-core with Linux bottle
                     # (verified formulae.brew.sh 2026-06).

# --- Traffic interception / proxying (Phase 3) -----------------------------
brew "proxify"       # HTTP/HTTPS/SOCKS traffic interception proxy for CLI tools
                     # (ProjectDiscovery). Route any tool through Burp or your own
                     # listener without proxy-aware client support: prefix the
                     # command with `proxify` and it rewrites the traffic. Go
                     # binary, confirmed in homebrew-core with Linux bottle
                     # (formulae.brew.sh/formula/proxify, verified 2026-06).
                     # Distinct from the brew `proxychains-ng` (which wraps
                     # syscalls); proxify operates at the HTTP layer.

# --- Offline password cracking (Phase 3) -----------------------------------
# Unprivileged, CPU/GPU-bound, no raw sockets -> host-side per the rubric.
# NOTE: john-jumbo provides the `john` binary and CONFLICTS with the plain
# `john` formula -- declare ONE, not both. Jumbo carries the hash formats
# pentesters actually want, so that is the one we pick.
brew "john-jumbo"    # John the Ripper (jumbo) -- many hash formats
brew "hashcat"       # GPU/CPU hash cracker (falls back to CPU with no GPU)

# --- Online login attacks (Phase 3) ----------------------------------------
# Connect-based brute forcing over normal TCP -- no CAP_NET_RAW needed, so
# host-side is fine (unprivileged connect-style traffic, same reasoning that
# used to justify host nmap's -sT before nmap moved fully to the container).
# Raw-socket SYN scanners (masscan / naabu) still belong in the Kali container.
brew "hydra"         # parallelized network login cracker (many protocols)
brew "ncrack"        # Nmap-project network auth cracker (overlaps hydra)

# --- Port scanning (Phase 3) -----------------------------------------------
# Connect-scan port discovery, unprivileged -- the host-side counterpart to
# nmap's raw-socket scanning, which now lives exclusively in the container
# (CAP_NET_RAW).
# IMPORTANT: rustscan's DEFAULT behavior is to auto-exec `nmap` on the open
# ports it finds. Since host nmap was removed (see the bootstrap note above),
# a plain `rustscan -a <target>` will find ports and then fail trying to run
# a nmap binary that doesn't exist on the host. Two ways to use it correctly:
#   1. `rustscan -a <target> --scripts none` -- ports only, no nmap auto-pipe.
#      Then feed the result into the container's nmap for service detection:
#      `kali nmap -sV -sC -p <ports> <target>` (see the `kali` shell function
#      in custom/aliases/system_files/etc/profile.d/spinofin-kali-aliases.sh).
#   2. Skip rustscan's nmap step entirely and just run the container's nmap
#      directly if you don't need rustscan's speed advantage on the initial
#      port sweep.
brew "rustscan"      # fast async connect port scanner; pair manually with the
                     # container's nmap (see note above) -- do not rely on its
                     # default auto-nmap behavior on this host.

# --- Exploit reference (Phase 3) -------------------------------------------
brew "exploitdb"     # local Exploit-DB archive + `searchsploit` lookup

# --- Pivoting / proxying (Phase 3) -----------------------------------------
brew "proxychains-ng" # route tool traffic through a SOCKS/HTTP proxy chain
                      # (provides the `proxychains4` binary)
brew "chisel-tunnel"  # fast TCP/UDP tunnel over HTTP for pivoting/port-forwarding
                      # (jpillora/chisel; provides the `chisel` binary -- the
                      # formula is named `chisel-tunnel` because `chisel` is a
                      # different, macOS-only tool)

# --- Networking utilities (Phase 3) ----------------------------------------
brew "netcat"        # the classic network swiss-army knife (banner grabbing,
                     # listeners, simple pivoting, file transfer)
brew "rlwrap"        # readline wrapper -- adds history/line-editing to tools
                     # that lack their own (e.g. raw netcat shells, msfconsole
                     # alternatives, some impacket interactive prompts)

# --- Python tooling bootstrap (Phase 3) ------------------------------------
# pipx is the installer for the host-side Python bucket (custom/pipx/*.pipx,
# installed via `ujust install-pipx-tools`). Installing it here means
# `ujust install-default-apps` makes pipx available before that recipe runs.
brew "pipx"          # isolated-venv installer for Python CLI apps
