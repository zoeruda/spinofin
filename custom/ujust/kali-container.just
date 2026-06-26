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
    # - msfdb init runs as your mapped user (NOT via sudo); it escalates
    #   internally for the postgres role/db creation. distrobox provides
    #   passwordless sudo inside the container.
    distrobox enter --root {{ kali_box }} -- bash -lc 'sudo service postgresql start; msfdb init'
    echo ""
    echo "Done. Launch Metasploit with:  msfconsole"
    echo "(or, explicitly:  distrobox enter --root {{ kali_box }} -- msfconsole)"

# Remove the Kali toolbox container entirely
[group('Kali')]
remove-kali:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Removing '{{ kali_box }}' ..."
    distrobox rm --root --force {{ kali_box }} || true
    echo "Removed. Note: the exported msfconsole wrapper in ~/.local/bin may"
    echo "remain; delete it manually if desired."
