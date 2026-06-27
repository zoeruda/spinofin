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
# Proved the brew + ujust path end-to-end before any other tooling. Note:
# unprivileged host nmap does CONNECT scans (-sT) fine; raw-socket SYN scans
# (-sS) are the rootful container's job (CAP_NET_RAW). Whether nmap should
# ALSO live in the Kali container is an open per-tool decision -- see README.
brew "nmap"

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

# --- Python tooling bootstrap (Phase 3) ------------------------------------
# pipx is the installer for the host-side Python bucket (custom/pipx/*.pipx,
# installed via `ujust install-pipx-tools`). Installing it here means
# `ujust install-default-apps` makes pipx available before that recipe runs.
brew "pipx"          # isolated-venv installer for Python CLI apps
