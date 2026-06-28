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
    # - postgresql is started via the sysv 'service' wrapper (the container is
    #   not an init/systemd container, so 'systemctl' is not used here).
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
    # BloodHound databases. It starts those services directly (not via systemd),
    # so it works in this non-init container. bloodhound is installed on demand
    # here rather than baked into the .ini because it pulls neo4j + a JVM and
    # not every user wants that weight. Idempotent: safe to re-run.
    distrobox enter --root {{ kali_box }} -- sudo bash -lc 'apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y bloodhound && bloodhound-setup'
    echo ""
    echo "Done. Start BloodHound with:  ujust bloodhound-start"
    echo "Then open the BloodHound UI (default http://localhost:8080) and change"
    echo "the default neo4j password as bloodhound-setup instructed."

# Start BloodHound CE -- the single 'get going' command, like Kali's bloodhound-start
[group('Kali')]
bloodhound-start:
    #!/usr/bin/env bash
    set -euo pipefail
    # Kali's `bloodhound-start` helper brings up the BloodHound CE stack.
    # CAVEAT: on stock Kali this manages a systemd unit (bloodhound.service).
    # This container is NOT an init/systemd container, so if bloodhound-start
    # shells out to systemctl it may not work unmodified -- UNVERIFIED here and
    # needs a real-boot check (see the README BloodHound note). Run setup first
    # if you have not:  ujust setup-bloodhound
    distrobox enter --root {{ kali_box }} -- sudo bloodhound-start

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
    distrobox enter --root {{ kali_box }} -- bash -lc 'n=0; for b in /usr/bin/impacket-*; do distrobox-export --bin "$b" --export-path "$HOME/.local/bin" >/dev/null 2>&1 || true; n=$((n + 1)); done; echo "Exported ${n} impacket-* commands to ~/.local/bin"'
    echo "Done. Try:  impacket-secretsdump -h   (runs in the container)"

# Expose the container's Kali wordlists to HOST-native tools (single copy, via $HOME)
[group('Kali')]
link-wordlists:
    #!/usr/bin/env bash
    set -euo pipefail
    # Host-native tools (ffuf, feroxbuster, gobuster, hydra, ...) cannot see the
    # container's /usr/share: distrobox shares only $HOME between host and
    # container, NOT the container's /usr. So a bare symlink to
    # /usr/share/seclists would be dead on the host. Instead we relocate each
    # tree ONCE into the shared $HOME (which the host sees directly) and symlink
    # the container's canonical /usr/share/<name> back to it -- single copy,
    # host gets the real files, the container keeps its standard paths.
    # Idempotent: skips trees already linked. Re-run after `rebuild-kali` (a
    # fresh assemble reinstalls the apt copy as a real dir). Uses the shared
    # rootful $HOME, so -- like the msfconsole/impacket exports -- confirm the
    # path on a real boot.
    distrobox enter --root {{ kali_box }} -- bash -lc 'set -euo pipefail; dest="$HOME/.local/share/spinofin/wordlists"; mkdir -p "$dest"; for name in seclists wordlists; do src="/usr/share/$name"; if [ -L "$src" ]; then echo "$src already linked -- skipping"; continue; fi; if [ ! -d "$src" ]; then echo "WARN: $src not found (run setup-kali first?)" >&2; continue; fi; [ -e "$dest/$name" ] || { echo "Copying $src -> $dest/$name (one-time, may be large)..."; cp -a "$src" "$dest/$name"; }; sudo rm -rf "$src"; sudo ln -sfn "$dest/$name" "$src"; echo "Linked /usr/share/$name -> $dest/$name"; done'
    ln -sfn "$HOME/.local/share/spinofin/wordlists" "$HOME/wordlists"
    echo ""
    echo "Done. Host-native tools can now use:"
    echo "  ~/wordlists/seclists     (also at ~/.local/share/spinofin/wordlists/seclists)"
    echo "  ~/wordlists/wordlists    (rockyou.txt.gz, etc.)"
    echo "The container still sees them at /usr/share/{seclists,wordlists}."

# Remove the Kali toolbox container entirely
[group('Kali')]
remove-kali:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Removing '{{ kali_box }}' ..."
    distrobox rm --root --force {{ kali_box }} || true
    echo "Removed. Note: the exported msfconsole wrapper in ~/.local/bin may"
    echo "remain; delete it manually if desired."
