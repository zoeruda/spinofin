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
    # spinofin-kali.ini sets replace=true on the [spinofin-kali] entry itself
    # (rebuild-kali relies on that). That means ANY `distrobox assemble
    # create` run against this manifest destroys and recreates an existing
    # container -- even here, with no --replace on the CLI. setup-kali is
    # meant to be the safe "make sure this exists" entry point, so it must
    # never call assemble against a container that's already there. Point to
    # rebuild-kali instead, which exists specifically to do that on purpose.
    if distrobox list --root 2>/dev/null | grep -q "{{ kali_box }}"; then
        echo "Container '{{ kali_box }}' already exists. setup-kali never"
        echo "touches an existing container (the manifest's replace=true would"
        echo "destroy it), so there's nothing to do here."
        echo "  ujust enter-kali    # use the existing container"
        echo "  ujust rebuild-kali  # destroy and recreate it from scratch"
        exit 0
    fi
    echo "Assembling '{{ kali_box }}' from {{ kali_ini }}"
    echo "First run is heavy: pulling kali-rolling + installing tools..."
    distrobox assemble create --file "{{ kali_ini }}"
    echo ""
    echo "Configuring the container's sudo prompt to show its hostname..."
    # Disambiguates host vs. container sudo prompts (e.g. "[sudo] password for
    # zoe (on spinofin-kali):" inside the box vs. "...(on <real-hostname>):" on
    # the host -- see custom/sudo-prompt/README.md for the host side). Written
    # as a NEW file under /etc/sudoers.d/ -- never touches the main sudoers
    # file, so this cannot lock out sudo even if something here were wrong;
    # at worst sudo just skips this one file with a warning. Mode 0440 +
    # root:root is REQUIRED for sudo to honor a sudoers.d file at all; no dot
    # in the filename either (sudo ignores dotted filenames in this directory).
    # Re-running `setup-kali` simply overwrites this file -- idempotent.
    distrobox enter --root {{ kali_box }} -- sudo bash -c 'printf "%s\n" "Defaults passprompt=\"[sudo] password for %p (on %h): \"" > /etc/sudoers.d/spinofin-sudo-prompt && chown root:root /etc/sudoers.d/spinofin-sudo-prompt && chmod 0440 /etc/sudoers.d/spinofin-sudo-prompt'
    echo "Container ready. Suggested next steps:"
    echo "  ujust setup-metasploit   # initialize the Metasploit database"
    echo "  ujust setup-bloodhound   # install + provision BloodHound CE"
    echo "  ujust setup-powerview    # install powerview.py via container-local pipx"
    echo "  ujust export-impacket    # surface impacket-* scripts to your host shell"
    echo "  ujust link-wordlists     # stage real wordlist files for host-native tools"
    echo "  ujust toggle-nmap        # choose where nmap lives (container/host/both/none)"
    echo "  ujust enter-kali         # drop into the container directly"
    echo "Run 'ujust --list' to see all available Kali recipes."

# Choose where nmap is installed: container-only (default), host-only, both, or none
[group('Kali')]
toggle-nmap:
    #!/usr/bin/env bash
    set -euo pipefail
    # nmap is baked into custom/distrobox/spinofin-kali.ini's additional_packages
    # (container side) AND is a real `depends_on "nmap"` of rustscan's
    # homebrew-core formula (host side, via custom/brew/default.Brewfile) -- so
    # "both" is the state a totally fresh setup/install-default-apps gives you
    # with zero extra steps; that's why it's the default below, not container-
    # only. This recipe manages the LIVE state on each side; it does not edit
    # either source of truth, so re-provisioning from either one brings its
    # copy of nmap back regardless of what you picked here (see the notes at
    # the end).
    echo "Where do you want nmap installed?"
    echo "  1. Both (default): brew's rustscan formula pulls in host nmap as a"
    echo "     real dependency anyway, so this is the natural resting state --"
    echo "     host nmap gets unprivileged connect scans (-sT) via brew, and"
    echo "     the container keeps full raw-socket scans (-sS, -O, --script)"
    echo "     via CAP_NET_RAW, run with the 'kali' alias."
    echo "  2. Container-only: full raw-socket scans (-sS, -O, --script) via"
    echo "     CAP_NET_RAW, run with the 'kali' alias -- recommended if you"
    echo "     want full scan capability without a duplicate host copy."
    echo "  3. Host-only: unprivileged connect scans only (-sT), no raw"
    echo "     sockets -- recommended for rustscan integration."
    echo "  4. None: bring your own scanner"
    read -rp "Enter a number [1-4]: " choice
    case "${choice}" in
        1) want_host=1; want_container=1 ;;
        2) want_host=0; want_container=1 ;;
        3) want_host=1; want_container=0 ;;
        4) want_host=0; want_container=0 ;;
        *)
            echo "ERROR: invalid choice '${choice}' -- expected 1, 2, 3, or 4." >&2
            exit 1
            ;;
    esac

    # --- Host side (brew; user-scoped, runtime-only, not baked into the image) ---
    if [ "${want_host}" -eq 1 ]; then
        if ! command -v brew >/dev/null 2>&1; then
            echo "ERROR: brew not found on host. Run 'ujust install-default-apps'" >&2
            echo "(or install Homebrew) first, then re-run 'ujust toggle-nmap'." >&2
            exit 1
        fi
        if brew list --formula nmap >/dev/null 2>&1; then
            echo "Host nmap: already installed (brew)."
        else
            echo "Installing host nmap (brew) -- unprivileged connect scans only (-sT)..."
            brew install nmap
        fi
    else
        if command -v brew >/dev/null 2>&1 && brew list --formula nmap >/dev/null 2>&1; then
            echo "Removing host nmap (brew)..."
            # --ignore-dependencies: rustscan's homebrew-core formula declares a
            # real `depends_on "nmap"` (it auto-execs nmap on the ports it finds --
            # see the Brewfile's rustscan note), so a plain `brew uninstall nmap`
            # refuses with "nmap is a dependency of rustscan" while rustscan is
            # installed. This only skips brew's own dependency check; it does not
            # touch rustscan, which still works standalone (`--scripts none` or
            # piping into the container's nmap -- see that same Brewfile note).
            brew uninstall --ignore-dependencies nmap
        else
            echo "Host nmap: already absent."
        fi
    fi

    # --- Container side (apt inside the rootful spinofin-kali container) ---
    if ! distrobox list --root 2>/dev/null | grep -q "{{ kali_box }}"; then
        if [ "${want_container}" -eq 1 ]; then
            echo "NOTE: container '{{ kali_box }}' doesn't exist yet. nmap is already"
            echo "baked into its manifest, so it will be present as soon as you run"
            echo "'ujust setup-kali' -- nothing more to do here."
        else
            echo "NOTE: container '{{ kali_box }}' doesn't exist yet -- skipping the container side."
        fi
    else
        if [ "${want_container}" -eq 1 ]; then
            distrobox enter --root {{ kali_box }} -- bash -lc '
                if command -v nmap >/dev/null 2>&1; then
                    echo "Container nmap: already installed."
                else
                    echo "Installing container nmap (apt, CAP_NET_RAW available)..."
                    sudo apt-get update -qq
                    sudo apt-get install -y nmap
                fi
            '
        else
            distrobox enter --root {{ kali_box }} -- bash -lc '
                if command -v nmap >/dev/null 2>&1; then
                    echo "Removing container nmap..."
                    sudo apt-get remove -y nmap
                else
                    echo "Container nmap: already absent."
                fi
            '
        fi
    fi

    echo ""
    echo "Done."
    if [ "${want_host}" -eq 0 ]; then
        echo "NOTE: rustscan's homebrew-core formula declares a real dependency on"
        echo "nmap, so 'ujust install-default-apps' (or 'install-all-brew') will pull"
        echo "host nmap back in the next time you run it -- that recipe now detects"
        echo "and repairs formulas with missing dependencies (via 'brew missing')."
        echo "Re-run 'ujust toggle-nmap' afterward if you want it removed again."
    fi
    if [ "${want_container}" -eq 0 ]; then
        echo "NOTE: nmap is still declared in custom/distrobox/spinofin-kali.ini's"
        echo "additional_packages, so 'ujust rebuild-kali' will reinstall it in the"
        echo "container (the manifest is the source of truth). 'ujust setup-kali'"
        echo "never touches an existing container, so it won't bring it back on its"
        echo "own. Re-run 'ujust toggle-nmap' after a rebuild if you want it removed"
        echo "again."
    fi

# Enter an interactive shell in the Kali toolbox container
[group('Kali')]
enter-kali:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v distrobox >/dev/null 2>&1; then
        echo "ERROR: distrobox not found on host." >&2
        exit 1
    fi
    if ! distrobox list --root 2>/dev/null | grep -q "{{ kali_box }}"; then
        echo "ERROR: container '{{ kali_box }}' not found." >&2
        echo "Run 'ujust setup-kali' first to provision it." >&2
        exit 1
    fi
    # Hand off to an interactive shell. --no-workdir forces entry at the
    # container's $HOME -- without it, distrobox preserves the host's cwd at
    # invocation time (mapped under /run/host/ in a rootful container), which
    # for a `ujust` recipe is wherever ujust itself was invoked from (e.g.
    # /run/host/usr/share/ublue-os/just) rather than anywhere useful inside
    # the box.
    # Leaving via Ctrl+C, Ctrl+D, or typing `exit` (which inherits your LAST
    # command's exit code -- possibly nonzero, e.g. if a scan you ran
    # reported "target down") are all normal, intentional ways out. None of
    # them mean THIS recipe failed, so we deliberately discard whatever exit
    # code the interactive session ends with.
    distrobox enter --root --no-workdir {{ kali_box }} || true

# Rebuild the Kali toolbox container from scratch (replaces the existing one)
[group('Kali')]
rebuild-kali:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! distrobox list --root 2>/dev/null | grep -q "{{ kali_box }}"; then
        echo "ERROR: container '{{ kali_box }}' not found." >&2
        echo "Nothing to rebuild -- run 'ujust setup-kali' to create it first." >&2
        exit 1
    fi
    echo "Replacing '{{ kali_box }}' from {{ kali_ini }} ..."
    distrobox assemble create --replace --file "{{ kali_ini }}"
    echo "Rebuilt. Re-run 'ujust setup-metasploit' to reinitialize the database."

# Initialize the Metasploit PostgreSQL database inside the container (re-runnable)
[group('Kali')]
setup-metasploit:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! distrobox list --root 2>/dev/null | grep -q "{{ kali_box }}"; then
        echo "ERROR: container '{{ kali_box }}' not found." >&2
        echo "Run 'ujust setup-kali' first to provision it." >&2
        exit 1
    fi
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
    if ! distrobox list --root 2>/dev/null | grep -q "{{ kali_box }}"; then
        echo "ERROR: container '{{ kali_box }}' not found." >&2
        echo "Run 'ujust setup-kali' first to provision it." >&2
        exit 1
    fi
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
    if ! distrobox list --root 2>/dev/null | grep -q "{{ kali_box }}"; then
        echo "ERROR: container '{{ kali_box }}' not found." >&2
        echo "Run 'ujust setup-kali' first to provision it." >&2
        exit 1
    fi
    # Without the guard above, running this against a missing/never-created
    # container falls through to distrobox's own auto-create prompt, which
    # builds a generic, non-manifest container with no init=true -- that box's
    # broken pty/systemd plumbing is what previously surfaced downstream as an
    # opaque "OCI runtime error: ptsname: Inappropriate ioctl for device"
    # (exit 255) instead of a clear "run setup-kali first" message.
    #
    # Kali's `bloodhound-start` waits for the API in a busy curl loop and then
    # runs xdg-open -- both of which hang in this headless, rootful container (no
    # browser, no display). So instead of the blocking wrapper we bring the
    # stack up ourselves and open the UI in your HOST browser.
    #
    # WHY THIS RE-RUNS bloodhound-setup (not a hand-rolled `systemctl start`):
    # after a host/container reboot NOTHING here auto-starts -- Kali ships
    # `bloodhound.service` DISABLED by default, and neo4j is not a systemd unit
    # at all (see below) -- so a plain `systemctl start bloodhound` on a cold
    # boot can come up before postgres/neo4j are actually ready, leaving the
    # API/UI unreachable (this was the bug: it "worked" only if you re-ran
    # `setup-bloodhound` first). `bloodhound-setup` is Kali's own proven,
    # idempotent sequence for bringing up postgres + the bloodhound DB + neo4j
    # correctly -- it does NOT reset an already-configured neo4j password or
    # blow away the database, it only acts on what isn't already running/
    # present. Re-running it here (every time) is what makes `bloodhound-start`
    # alone sufficient after a reboot. It does NOT touch apt, so it is fast and
    # works fully offline. If this errors with "System has not been booted with
    # systemd as init system", the container predates init=true: `ujust
    # rebuild-kali`, then `ujust setup-bloodhound` again.
    #
    # NEO4J IS NOT A SYSTEMD UNIT HERE: Kali's bloodhound package starts/stops
    # neo4j directly via its own `neo4j` binary (LSB-style start/status), not
    # via a neo4j.service unit -- confirmed by bloodhound-setup's own output
    # ("Starting Neo4j... Started neo4j (pid:...)") and by bloodhound-stop
    # checking neo4j's status SEPARATELY from bloodhound.service's systemd
    # status. So a warning like "Unit neo4j.service not found" (e.g. from
    # bloodhound.service's own unit file referencing it) is EXPECTED and safe
    # to ignore -- bloodhound-setup already brings neo4j up the correct way.
    distrobox enter --root {{ kali_box }} -- sudo bash -lc '
        if ! command -v bloodhound-setup >/dev/null 2>&1; then
            echo "ERROR: BloodHound is not installed yet. Run: ujust setup-bloodhound" >&2
            exit 1
        fi
        shim=/tmp/spinofin-nobrowser
        mkdir -p "$shim"
        for b in xdg-open sensible-browser x-www-browser www-browser gnome-www-browser firefox; do
            printf "#!/bin/sh\nexit 0\n" > "$shim/$b"
            chmod +x "$shim/$b"
        done
        PATH="$shim:$PATH" BROWSER=true bloodhound-setup >/dev/null
        systemctl start --no-block bloodhound || true
    '
    echo ""
    echo "BloodHound is starting in the background (give it ~30s)."
    echo "Open the UI in your HOST browser:  http://localhost:8080"
    echo "Check status:  distrobox enter --root {{ kali_box }} -- sudo systemctl status bloodhound"
    echo "Check neo4j directly (not systemd-managed here):  distrobox enter --root {{ kali_box }} -- sudo neo4j status"
    echo ""
    echo "NOTE: a warning mentioning 'neo4j.service' (e.g. 'Unit neo4j.service"
    echo "not found') is EXPECTED and safe to ignore. Kali's bloodhound package"
    echo "manages neo4j directly via its own binary, not as a systemd unit --"
    echo "the step above already started/verified it that way, so the database"
    echo "is up regardless of that message."

# Surface the container's impacket-* scripts to the host shell (distrobox export)
[group('Kali')]
export-impacket:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! distrobox list --root 2>/dev/null | grep -q "{{ kali_box }}"; then
        echo "ERROR: container '{{ kali_box }}' not found." >&2
        echo "Run 'ujust setup-kali' first to provision it." >&2
        exit 1
    fi
    # impacket lives ONLY in the container (impacket-scripts in the .ini). This
    # exports every /usr/bin/impacket-* wrapper to the host as a distrobox
    # shortcut in ~/.local/bin, so `impacket-secretsdump` (etc.) run from the
    # host shell execute in the container -- one source of truth, no host copy
    # to drift. Re-runnable; new scripts appear after a container update + re-run.
    # NOTE: uses the same rootful distrobox-export path as the msfconsole export,
    # so it inherits the same rootful-$HOME considerations -- validate on real boot.
    distrobox enter --root {{ kali_box }} -- bash -lc 'n=0; for b in /usr/bin/impacket-*; do distrobox-export --bin "$b" --export-path "$HOME/.local/bin" >/dev/null 2>&1 || true; n=$((n + 1)); done; echo "Exported ${n} impacket-* commands to ~/.local/bin"'
    echo "Done. Run impacket-secretsdump (etc.) straight from your shell."

# Expose the container's Kali wordlists to HOST-native tools (single copy, via $HOME)
[group('Kali')]
link-wordlists:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! distrobox list --root 2>/dev/null | grep -q "{{ kali_box }}"; then
        echo "ERROR: container '{{ kali_box }}' not found." >&2
        echo "Run 'ujust setup-kali' first to provision it." >&2
        exit 1
    fi
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

# Install powerview (aniqfakhrul/powerview.py) inside the container via pipx (re-runnable)
[group('Kali')]
setup-powerview:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! distrobox list --root 2>/dev/null | grep -q "{{ kali_box }}"; then
        echo "ERROR: container '{{ kali_box }}' not found." >&2
        echo "Run 'ujust setup-kali' first to provision it." >&2
        exit 1
    fi
    echo "Installing powerview inside '{{ kali_box }}' via container-local pipx..."
    # powerview's gssapi dependency has no Linux manylinux wheel and always
    # builds from source, requiring BOTH the krb5 headers (libkrb5-dev) and
    # the Python.h headers (python3-dev) to compile its C extension -- missing
    # either one fails the build (python3-dev's absence used to surface as
    # "Python.h: No such file or directory" even with libkrb5-dev present).
    # Those are absent on Bluefin and forbidden by the no-layering policy, so
    # host-side pipx can never install this. libkrb5-dev, python3-dev, and
    # pipx are all baked into the container's additional_packages specifically
    # to make this work.
    #
    # NOTE ON THE COMMAND NAME: the package is named powerview.py (the repo
    # name), but the installed console script is just `powerview` -- per the
    # project's own install docs. `powerview.py` is not a valid command.
    #
    # ISOLATED PIPX_HOME/PIPX_BIN_DIR: distrobox shares $HOME between host and
    # this rootful container by default, which means the default pipx target
    # (~/.local/bin) is the SAME physical directory as the host's own brew-
    # managed pipx. That collides two independent pipx installs (host and
    # container) into one shared bin directory. We redirect pipx's venv store
    # AND its bin dir to /opt/spinofin/pipx, which lives in the container's
    # OWN root filesystem -- NOT under $HOME, so it is invisible to the host
    # entirely (distrobox does not share /opt, only $HOME). This keeps Kali's
    # pipx tools fully separate from host pipx tools without needing a second,
    # separate container $HOME (which would also break the OTHER recipes that
    # rely on the shared $HOME working as-is: export-impacket, link-wordlists,
    # and the msfconsole export in setup-kali).
    #
    # /usr/local/bin SYMLINK: a non-interactive `kali powerview ...` call
    # (custom/aliases/system_files/etc/profile.d/spinofin-kali-aliases.sh)
    # does not source ~/.bashrc, so a plain PATH addition there is invisible
    # to it -- this is why `kali powerview` previously failed with "not
    # found" even though it worked from an interactive `ujust enter-kali`
    # shell. /usr/local/bin is on the system's default PATH unconditionally,
    # for every shell invocation style (interactive, login, or not), so a
    # single symlink there makes `powerview` reachable everywhere INSIDE the
    # container without depending on any shell rc file. Since the container's
    # /usr/local/bin is part of its own private root filesystem (not shared
    # with the host), this is still "only inside Kali" -- the host's own
    # /usr/local/bin is an entirely separate, untouched directory.
    # Idempotent: pipx install --force and ln -sf handle re-runs cleanly.
    distrobox enter --root {{ kali_box }} -- bash -lc '
        set -euo pipefail
        export PIPX_HOME="/opt/spinofin/pipx"
        export PIPX_BIN_DIR="/opt/spinofin/pipx/bin"
        sudo mkdir -p "$PIPX_HOME" "$PIPX_BIN_DIR"
        sudo chown -R "$(id -u):$(id -g)" "$PIPX_HOME"
        pipx install --force "git+https://github.com/aniqfakhrul/powerview.py"
        sudo ln -sf "$PIPX_BIN_DIR/powerview" /usr/local/bin/powerview
    '
    echo ""
    echo "Done. powerview is now on PATH everywhere inside the container:"
    echo "  ujust enter-kali   # then: powerview --help"
    echo "  kali powerview --help   # using the kali alias, from your host shell"

# Remove the Kali toolbox container entirely
[group('Kali')]
remove-kali:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Removing '{{ kali_box }}' ..."
    distrobox rm --root --force {{ kali_box }} || true
    echo "Removed."
