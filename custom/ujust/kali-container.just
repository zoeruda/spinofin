# vim: set ft=make :
#########################
### kali-container.just
#########################
## Kali "toolbox" container management (Phase 2).
##
## The container is DECLARED in custom/distrobox/spinofin-kali.ini, which the
## build copies into the image at /usr/share/spinofin/distrobox/. These recipes
## just drive distrobox against that manifest -- the manifest is the source of
## truth, not these commands.
##
## Rootful container: management needs privilege, but do NOT wrap the assemble
## command in sudo (see the manifest's IMPORTANT note). root=true in the INI
## handles escalation while keeping exports in your user's ~/.local/bin.

kali_ini := "/usr/share/spinofin/distrobox/spinofin-kali.ini"
kali_box := "spinofin-kali"

# Provision the rootful Kali toolbox container from its manifest (HEAVY first run)
[group('Kali')]
setup-kali:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v distrobox >/dev/null 2>&1; then
        echo "ERROR: distrobox not found on host." >&2
        exit 1
    fi
    if [ ! -f "{{ kali_ini }}" ]; then
        echo "ERROR: manifest not found at {{ kali_ini }}" >&2
        exit 1
    fi
    echo "Assembling '{{ kali_box }}' from {{ kali_ini }}"
    echo "Run as your normal user (not sudo); root=true in the INI handles"
    echo "escalation and keeps the msfconsole export in ~/.local/bin."
    echo "First run is heavy: pulling kali-rolling + installing tools..."
    distrobox assemble create --file "{{ kali_ini }}"
    echo ""
    echo "Container ready. Next:"
    echo "  ujust setup-metasploit   # initialize the Metasploit database"
    echo "  ujust enter-kali         # drop into the container"

# Enter an interactive shell in the Kali toolbox container
[group('Kali')]
enter-kali:
    #!/usr/bin/env bash
    set -euo pipefail
    distrobox enter --root {{ kali_box }}

# Rebuild the Kali toolbox container from scratch (replaces the existing one)
[group('Kali')]
rebuild-kali:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Replacing '{{ kali_box }}' from {{ kali_ini }} ..."
    distrobox assemble create --replace --file "{{ kali_ini }}"
    echo "Rebuilt. Re-run 'ujust setup-metasploit' to reinitialize the database."

# Initialize the Metasploit PostgreSQL database inside the container (re-runnable)
[group('Kali')]
setup-metasploit:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Starting PostgreSQL and initializing the Metasploit database..."
    # Runs inside the rootful Kali container. Idempotent: safe to re-run.
    # - postgresql is started via the 'service' wrapper (still works now that
    #   the box is an init container; 'systemctl start postgresql' works too).
    # - msfdb MUST be run as root on current Kali (it guards at the top and
    #   exits otherwise). It writes a SYSTEM-WIDE config to
    #   /usr/share/metasploit-framework/config/database.yml, so the exported
    #   msfconsole -- which runs as your user -- reads the same config and
    #   connects to the same database. distrobox provides passwordless sudo
    #   inside the container.
    distrobox enter --root {{ kali_box }} -- bash -lc 'sudo service postgresql start; sudo msfdb init'
    echo ""
    echo "Done. Launch Metasploit with:  msfconsole"
    echo "(or, explicitly:  distrobox enter --root {{ kali_box }} -- msfconsole)"

# Install BloodHound CE in the container and provision its databases (re-runnable)
[group('Kali')]
setup-bloodhound:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Installing BloodHound CE and provisioning its databases..."
    # Mirrors `setup-metasploit`. Kali's `bloodhound` package ships the
    # bloodhound-setup helper, which starts PostgreSQL + neo4j and creates the
    # BloodHound databases. The box is an init container (init=true in the .ini),
    # so systemd-managed services work. bloodhound is installed on demand here
    # rather than baked into the .ini because it pulls neo4j + a JVM and not
    # every user wants that weight. Idempotent: safe to re-run.
    #
    # HEADLESS FIX: bloodhound-setup ends by trying to xdg-open the neo4j page in
    # a browser, which has no display/browser in this container and makes the
    # command fail. We shim the browser launchers to no-ops (PATH + BROWSER) so
    # setup completes cleanly; you open the neo4j page in your HOST browser
    # instead (instructions printed below). Real (non-browser) failures still
    # surface, since we only neutralize the browser step.
    distrobox enter --root {{ kali_box }} -- sudo bash -lc 'set -e; apt-get update; DEBIAN_FRONTEND=noninteractive apt-get install -y bloodhound; shim=/tmp/spinofin-nobrowser; mkdir -p "$shim"; for b in xdg-open sensible-browser x-www-browser www-browser gnome-www-browser firefox; do printf "#!/bin/sh\nexit 0\n" > "$shim/$b"; chmod +x "$shim/$b"; done; PATH="$shim:$PATH" BROWSER=true bloodhound-setup'
    echo ""
    echo "Done -- BloodHound databases are provisioned. Now, from your HOST browser:"
    echo "  1. Open http://localhost:7474 (neo4j), log in neo4j / neo4j, set a new password."
    echo "  2. Put that password into the container config:"
    echo "       distrobox enter --root {{ kali_box }} -- sudo nano /etc/bhapi/bhapi.json"
    echo "  3. Start BloodHound:  ujust bloodhound-start   (UI at http://localhost:8080)"

# Start BloodHound CE -- the single 'get going' command, like Kali's bloodhound-start
[group('Kali')]
bloodhound-start:
    #!/usr/bin/env bash
    set -euo pipefail
    # Kali's `bloodhound-start` waits for the API in a busy curl loop and then
    # runs xdg-open -- both of which hang in this headless, rootful container (no
    # browser, no display). So instead of the blocking wrapper we start the
    # systemd units directly and NON-BLOCKING (`--no-block`), and you open the UI
    # in your HOST browser. The stack comes up in the background. If this errors
    # with "System has not been booted with systemd as init system", the
    # container predates init=true: `ujust rebuild-kali`, then `ujust
    # setup-bloodhound` again. Run setup first if you have not.
    distrobox enter --root {{ kali_box }} -- sudo bash -lc 'for svc in postgresql neo4j bloodhound; do systemctl start --no-block "$svc" || true; done'
    echo ""
    echo "BloodHound is starting in the background (give it ~30s)."
    echo "Open the UI in your HOST browser:  http://localhost:8080"
    echo "Check status:  distrobox enter --root {{ kali_box }} -- sudo systemctl status bloodhound"

# Surface the container's impacket-* scripts to the host shell (distrobox export)
[group('Kali')]
export-impacket:
    #!/usr/bin/env bash
    set -euo pipefail
    # impacket lives ONLY in the container (impacket-scripts in the .ini). This
    # exports every /usr/bin/impacket-* wrapper to the host as a distrobox
    # shortcut in ~/.local/bin, so `impacket-secretsdump` (etc.) run from the
    # host shell execute in the container -- one source of truth, no host copy
    # to drift. Re-runnable; new scripts appear after a container update + re-run.
    # NOTE: uses the same rootful distrobox-export path as the msfconsole export,
    # so it inherits the same rootful-$HOME considerations -- validate on real boot.
    #
    # PRIVILEGE CAVEAT: the exported ~/.local/bin wrappers enter the container as
    # your USER (unprivileged). Several impacket tools need root INSIDE the
    # container -- e.g. raw sockets / low ports for ntlmrelayx, the ICMP/ping
    # paths, rpcdump on some transports. Those work with sudo in the container
    # but fail through the plain exported wrapper. To run one as root in the
    # container FROM THE HOST, bypass the wrapper and use the container's sudo:
    #     distrobox enter --root {{ kali_box }} -- sudo impacket-ntlmrelayx <args>
    # (general form: distrobox enter --root {{ kali_box }} -- sudo impacket-<tool> <args>)
    distrobox enter --root {{ kali_box }} -- bash -lc 'n=0; for b in /usr/bin/impacket-*; do distrobox-export --bin "$b" --export-path "$HOME/.local/bin" >/dev/null 2>&1 || true; n=$((n + 1)); done; echo "Exported ${n} impacket-* commands to ~/.local/bin"'
    echo "Done. Unprivileged tools: run impacket-secretsdump (etc.) straight from your shell."
    echo "Tools needing root in the container (e.g. ntlmrelayx) -- run with the container's sudo:"
    echo "  distrobox enter --root {{ kali_box }} -- sudo impacket-<tool> <args>"

# Expose the container's Kali wordlists to HOST-native tools (single copy, via $HOME)
[group('Kali')]
link-wordlists:
    #!/usr/bin/env bash
    set -euo pipefail
    # Make the container's Kali wordlists usable by HOST-native tools (john,
    # hashcat, ffuf, ...). Two gotchas: (1) distrobox shares only $HOME -- not
    # the container's /usr -- so files must land under $HOME; and (2)
    # /usr/share/wordlists is mostly SYMLINKS into other packages' dirs (dirb,
    # wfuzz, metasploit, ...), many of them DANGLING, which are useless on the
    # host. So we stage REAL files only: relocate the seclists tree (its password
    # lists are real files) into $HOME and symlink /usr/share/seclists back, and
    # decompress rockyou into a ready-to-use plaintext list. We do NOT mirror the
    # /usr/share/wordlists symlink farm. Idempotent. Re-run after `rebuild-kali`.
    # Uses the shared rootful $HOME -- confirm on a real boot.
    distrobox enter --root {{ kali_box }} -- bash -lc 'set -euo pipefail; dest="$HOME/.local/share/spinofin/wordlists"; mkdir -p "$dest"; if [ -L /usr/share/seclists ]; then echo "seclists already linked"; elif [ -d /usr/share/seclists ]; then [ -e "$dest/seclists" ] || { echo "Copying seclists (one-time, ~1GB)..."; cp -a /usr/share/seclists "$dest/seclists"; }; sudo rm -rf /usr/share/seclists; sudo ln -sfn "$dest/seclists" /usr/share/seclists; echo "Linked /usr/share/seclists -> $dest/seclists"; else echo "WARN: /usr/share/seclists missing (run setup-kali first?)" >&2; fi; if [ -f /usr/share/wordlists/rockyou.txt.gz ]; then [ -f "$dest/rockyou.txt" ] || { echo "Decompressing rockyou.txt..."; gunzip -c /usr/share/wordlists/rockyou.txt.gz > "$dest/rockyou.txt"; }; elif [ -f /usr/share/wordlists/rockyou.txt ]; then cp -n /usr/share/wordlists/rockyou.txt "$dest/rockyou.txt"; else echo "WARN: rockyou not found under /usr/share/wordlists" >&2; fi; echo "Staged real files in $dest"'
    ln -sfn "$HOME/.local/share/spinofin/wordlists" "$HOME/wordlists"
    echo ""
    echo "Done. Real, host-usable wordlists for john / hashcat:"
    echo "  ~/wordlists/rockyou.txt"
    echo "  ~/wordlists/seclists/Passwords/...   (xato-net, Common-Credentials, etc.)"
    echo "Examples:"
    echo "  hashcat -m 0 -a 0 hashes.txt ~/wordlists/rockyou.txt"
    echo "  john --wordlist=\$HOME/wordlists/rockyou.txt hashes.txt"

# Remove the Kali toolbox container entirely
[group('Kali')]
remove-kali:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Removing '{{ kali_box }}' ..."
    distrobox rm --root --force {{ kali_box }} || true
    echo "Removed. Note: the exported msfconsole wrapper in ~/.local/bin may"
    echo "remain; delete it manually if desired."
