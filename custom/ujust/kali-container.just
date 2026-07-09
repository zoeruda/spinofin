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
    # distrobox prints its own concise progress to the terminal here (the
    # "distrobox: Installing basic packages..." / "[ OK ]" lines) -- we let it
    # through untouched, so the console looks exactly like a normal distrobox
    # run. The catch: distrobox DISCARDS the container's raw apt output before
    # it reaches that stream, so when apt fails it only says "Container Setup
    # Failure!" with no detail. So ON FAILURE we pull the container's FULL raw
    # init log (every apt line + the real error) straight from podman's own log
    # store -- the one place that detail survives distrobox's filtering -- and
    # print its tail so the exact error is visible immediately.
    set +e
    distrobox assemble create --file "{{ kali_ini }}"
    rc=$?
    set -e
    if [ "${rc}" -ne 0 ]; then
        echo "" >&2
        echo "ERROR: assembling '{{ kali_box }}' failed (exit ${rc})." >&2
        # Rootful box -> its podman container lives in root's storage, so the
        # logs need `sudo podman` (assumes podman, Bluefin's default). Read the
        # log BEFORE the cleanup below removes the container. Best-effort: if the
        # container was never created there is simply nothing to read.
        log_dir="${HOME}/.local/share/spinofin/logs"
        mkdir -p "${log_dir}"
        log="${log_dir}/setup-kali-$(date +%Y%m%d-%H%M%S).log"
        sudo podman logs {{ kali_box }} >"${log}" 2>&1 || true
        echo "Full container log saved to: ${log}" >&2
        echo "----- last 40 lines of the log -----" >&2
        tail -n 40 "${log}" >&2 || true
        echo "------------------------------------" >&2
        # setup-kali's guard (top of this recipe) refuses to run while a
        # container named '{{ kali_box }}' exists, because the manifest would
        # replace it. A failed assemble leaves a PARTIAL container behind, which
        # would trip that guard and block a plain re-run. Remove it so
        # 'ujust setup-kali' can simply be run again. (rebuild-kali does the
        # opposite on failure -- it KEEPS the partial container, because its own
        # guard requires one to exist.)
        echo "Removing the partial container so 'ujust setup-kali' can be re-run..." >&2
        distrobox rm --root --force {{ kali_box }} >/dev/null 2>&1 || true
        exit "${rc}"
    fi
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
    # NOTE: rebuild-kali repeats this exact command (a --replace wipes the file);
    # KEEP THE TWO BYTE-FOR-BYTE IDENTICAL so both recipes yield the same container.
    distrobox enter --root {{ kali_box }} -- sudo bash -c 'printf "%s\n" "Defaults passprompt=\"[sudo] password for %p (on %h): \"" > /etc/sudoers.d/spinofin-sudo-prompt && chown root:root /etc/sudoers.d/spinofin-sudo-prompt && chmod 0440 /etc/sudoers.d/spinofin-sudo-prompt'
    echo "Container ready. Suggested next steps:"
    echo "  ujust setup-metasploit   # initialize the Metasploit database"
    echo "  ujust setup-bloodhound   # install + provision BloodHound CE"
    echo "  ujust setup-powerview    # install powerview.py via container-local pipx"
    echo "  ujust setup-kerbrute     # install kerbrute via container-local go install"
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
    # Same intermittent failure point as setup-kali (the container's init runs
    # apt after "distrobox: Installing basic packages..."). We let distrobox
    # print its normal progress to the console; distrobox discards the raw apt
    # output, so ON FAILURE we pull the container's FULL raw init log (every apt
    # line + the real error) straight from podman's own log store and print its
    # tail. See setup-kali for the fuller rationale.
    set +e
    distrobox assemble create --replace --file "{{ kali_ini }}"
    rc=$?
    set -e
    if [ "${rc}" -ne 0 ]; then
        echo "" >&2
        echo "ERROR: rebuilding '{{ kali_box }}' failed (exit ${rc})." >&2
        # Rootful box -> logs need `sudo podman` (assumes podman, Bluefin's
        # default). Best-effort; nothing to read if the container is absent.
        log_dir="${HOME}/.local/share/spinofin/logs"
        mkdir -p "${log_dir}"
        log="${log_dir}/rebuild-kali-$(date +%Y%m%d-%H%M%S).log"
        sudo podman logs {{ kali_box }} >"${log}" 2>&1 || true
        echo "Full container log saved to: ${log}" >&2
        echo "----- last 40 lines of the log -----" >&2
        tail -n 40 "${log}" >&2 || true
        echo "------------------------------------" >&2
        # Unlike setup-kali, we deliberately DO NOT remove the container here.
        # rebuild-kali's guard (top of this recipe) requires a container named
        # '{{ kali_box }}' to already exist, and --replace leaves a partial one
        # behind on a failed run. Keeping it means 'ujust rebuild-kali' can just
        # be run again -- its --replace destroys and recreates it. If the box is
        # wedged past that, reboot, or 'ujust remove-kali && ujust setup-kali'.
        exit "${rc}"
    fi
    # Re-apply the container's sudo-prompt drop-in. --replace recreates the box
    # from the image, which WIPES /etc/sudoers.d/spinofin-sudo-prompt -- that
    # file is written here at runtime, not baked into the image or the manifest,
    # so without this step a rebuilt container would differ from a setup-kali
    # one (no hostname in its sudo prompt). KEEP THIS COMMAND BYTE-FOR-BYTE
    # IDENTICAL to the one in setup-kali (see the fuller rationale there); the
    # two together are what make setup-kali and rebuild-kali yield an identical
    # container. Idempotent: it just overwrites the file.
    echo "Reconfiguring the container's sudo prompt to show its hostname..."
    distrobox enter --root {{ kali_box }} -- sudo bash -c 'printf "%s\n" "Defaults passprompt=\"[sudo] password for %p (on %h): \"" > /etc/sudoers.d/spinofin-sudo-prompt && chown root:root /etc/sudoers.d/spinofin-sudo-prompt && chmod 0440 /etc/sudoers.d/spinofin-sudo-prompt'
    echo "Rebuilt. --replace wipes everything not baked into the manifest, so"
    echo "any container-side setup you'd done before is gone too. If you relied"
    echo "on it, re-run what you need:"
    echo "  ujust setup-metasploit   # re-initialize the Metasploit database"
    echo "  ujust setup-bloodhound   # re-install + provision BloodHound CE"
    echo "  ujust setup-powerview    # re-install powerview.py via container-local pipx"
    echo "  ujust setup-kerbrute     # re-install kerbrute via container-local go install"
    echo "  ujust export-impacket    # re-surface impacket-* scripts to your host shell"
    echo "  ujust toggle-nmap        # re-choose where nmap lives (container/host/both/none)"

# Initialize the Metasploit PostgreSQL database inside the container (run ONCE)
[group('Kali')]
setup-metasploit:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! distrobox list --root 2>/dev/null | grep -q "{{ kali_box }}"; then
        echo "ERROR: container '{{ kali_box }}' not found." >&2
        echo "Run 'ujust setup-kali' first to provision it." >&2
        exit 1
    fi
    # Ensure this recipe's container packages are present. Normally they come
    # from spinofin-kali.ini at assemble time; installing on demand here (same
    # container-local apt path as toggle-nmap/setup-bloodhound -- does not touch
    # the host or the no-layering policy) makes the recipe self-sufficient if the
    # container drifted or the .ini was edited without a rebuild. dpkg -s (not
    # command -v) so metapackages/data packages are detected by package name.
    distrobox enter --root {{ kali_box }} -- bash -lc '
        set -euo pipefail
        missing=()
        for pkg in metasploit-framework postgresql; do
            dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
        done
        if [ "${#missing[@]}" -gt 0 ]; then
            echo "Installing missing container packages: ${missing[*]}"
            sudo apt-get update -qq
            sudo apt-get install -y "${missing[@]}"
        fi
    '
    echo "Starting PostgreSQL and initializing the Metasploit database..."
    # Runs inside the rootful Kali container.
    # - Kali ships postgresql.service DISABLED by default (confirmed by
    #   Kali's own docs: `sudo msfdb status` shows "Loaded: ... disabled;
    #   vendor preset: disabled"). That's the actual bug behind "the DB
    #   doesn't persist across reboots" -- postgres was never coming back on
    #   its own, so the only documented recovery was re-running this whole
    #   recipe, which re-runs `msfdb init` on every single reboot.
    # - `systemctl enable` (once, here) fixes that at the root: this
    #   container is an init container (init=true in the .ini), so once
    #   postgresql is enabled, systemd starts it automatically every time the
    #   container's init boots -- including a stopped container being
    #   auto-started by a plain `distrobox enter`, which is exactly what the
    #   exported msfconsole/msfvenom wrappers below do under the hood. No
    #   ujust command, and no msfdb call, is needed again after a reboot.
    # - msfdb MUST be run as root on current Kali (it guards at the top and
    #   exits otherwise). It writes a SYSTEM-WIDE config to
    #   /usr/share/metasploit-framework/config/database.yml, so the exported
    #   msfconsole -- which runs as your user -- reads the same config and
    #   connects to the same database. distrobox provides passwordless sudo
    #   inside the container.
    # - This recipe only needs to run ONCE. `msfdb init` is the one command
    #   here that touches the database schema, and it's kept OUT of any
    #   reboot-time path on purpose -- there's no "rerun this after every
    #   reboot" step left for it to accidentally wipe a case's data with.
    distrobox enter --root {{ kali_box }} -- bash -lc 'sudo systemctl enable --now postgresql; sudo msfdb init'
    echo ""
    echo "Exporting msfconsole and msfvenom to the host..."
    # Exported HERE rather than declaratively in the manifest: that way they
    # only ever appear/refresh right after the database is actually ready,
    # instead of at setup-kali/rebuild-kali time (when msfdb hasn't run yet).
    # Same rootful distrobox-export path as export-impacket; `|| true` per
    # export so one failing (e.g. already exported) doesn't abort the other.
    # Idempotent: re-running just refreshes both wrapper scripts.
    distrobox enter --root {{ kali_box }} -- bash -lc '
        distrobox-export --bin /usr/bin/msfconsole --export-path "$HOME/.local/bin" >/dev/null 2>&1 || true
        distrobox-export --bin /usr/bin/msfvenom --export-path "$HOME/.local/bin" >/dev/null 2>&1 || true
    '
    echo ""
    echo "Done. Launch Metasploit with:  msfconsole"
    echo "Generate payloads with:        msfvenom"
    echo "(or, explicitly:  distrobox enter --root {{ kali_box }} -- msfconsole)"
    echo ""
    echo "You only need this ONCE. PostgreSQL is now enabled inside the"
    echo "container, so it comes back on its own after every reboot -- just"
    echo "run 'msfconsole' directly. There is no need to re-run"
    echo "'ujust setup-metasploit' (which is the only path here that touches"
    echo "the database)."

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
    # Ensure impacket is present before exporting: without it the glob below
    # matches nothing and the recipe would "export" the literal /usr/bin/impacket-*
    # and claim success. Normally from spinofin-kali.ini; installed on demand here
    # (container-local apt -- does not touch the host or the no-layering policy).
    distrobox enter --root {{ kali_box }} -- bash -lc '
        set -euo pipefail
        if ! dpkg -s impacket-scripts >/dev/null 2>&1; then
            echo "Installing missing container package: impacket-scripts"
            sudo apt-get update -qq
            sudo apt-get install -y impacket-scripts
        fi
    '
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
    # /usr/share/wordlists symlink farm. Idempotent. Does NOT need a re-run after
    # `rebuild-kali`: everything this recipe produces (~/wordlists/... and its
    # target under ~/.local/share/spinofin/wordlists) lives under $HOME, which
    # distrobox bind-mounts from the HOST -- --replace only recreates the
    # container's own root filesystem, never touching $HOME. The one thing a
    # rebuild resets is the container-internal /usr/share/seclists symlink this
    # recipe points back at $HOME (a disk-dedup nicety so the ~1GB tree doesn't
    # exist twice inside that one container) -- nothing host-facing depends on
    # that, so it's fine left alone; re-running this recipe just re-establishes it.
    # Uses the shared rootful $HOME -- confirm on a real boot.
    # Ensure the wordlist packages are present before staging. Normally from
    # spinofin-kali.ini; installed on demand here (container-local apt -- does not
    # touch the host or the no-layering policy) so a missing tree becomes an
    # install rather than a WARN + empty result. dpkg -s is checked (not the
    # /usr/share path) so a tree this recipe has already relocated into $HOME --
    # leaving /usr/share/seclists as a symlink -- is NOT treated as missing and
    # needlessly reinstalled (~1GB).
    distrobox enter --root {{ kali_box }} -- bash -lc '
        set -euo pipefail
        missing=()
        for pkg in seclists wordlists; do
            dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
        done
        if [ "${#missing[@]}" -gt 0 ]; then
            echo "Installing missing container packages (~1GB+): ${missing[*]}"
            sudo apt-get update -qq
            sudo apt-get install -y "${missing[@]}"
        fi
    '
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
    # and the msfconsole/msfvenom exports in setup-metasploit).
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
    # Idempotent: pipx install --force, ln -sf, and the export below all
    # handle re-runs cleanly.
    # Ensure pipx and powerview's build deps are present. Normally from
    # spinofin-kali.ini; installed on demand here (container-local apt -- does not
    # touch the host or the no-layering policy) so this recipe doesn't fail with
    # "pipx: not found" or a gssapi build error if the container drifted.
    distrobox enter --root {{ kali_box }} -- bash -lc '
        set -euo pipefail
        missing=()
        for pkg in pipx libkrb5-dev python3-dev; do
            dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
        done
        if [ "${#missing[@]}" -gt 0 ]; then
            echo "Installing missing container packages: ${missing[*]}"
            sudo apt-get update -qq
            sudo apt-get install -y "${missing[@]}"
        fi
    '
    distrobox enter --root {{ kali_box }} -- bash -lc '
        set -euo pipefail
        export PIPX_HOME="/opt/spinofin/pipx"
        export PIPX_BIN_DIR="/opt/spinofin/pipx/bin"
        sudo mkdir -p "$PIPX_HOME" "$PIPX_BIN_DIR"
        sudo chown -R "$(id -u):$(id -g)" "$PIPX_HOME"
        pipx install --force "git+https://github.com/aniqfakhrul/powerview.py"
        sudo ln -sf "$PIPX_BIN_DIR/powerview" /usr/local/bin/powerview
        # Export the /usr/local/bin symlink (not the PIPX_BIN_DIR target
        # directly) to the host, same rootful distrobox-export path as
        # export-impacket and the setup-metasploit exports. Only possible
        # failure here is a re-export of an identical wrapper, hence || true.
        distrobox-export --bin /usr/local/bin/powerview --export-path "$HOME/.local/bin" >/dev/null 2>&1 || true
    '
    echo ""
    echo "Done. powerview is now on PATH everywhere inside the container, AND"
    echo "exported straight to your host shell:"
    echo "  powerview --help        # from your host shell directly"
    echo "  kali powerview --help   # equivalent, using the kali alias"
    echo "  ujust enter-kali        # then: powerview --help"

# Install kerbrute (ropnop/kerbrute) inside the container via go install (re-runnable)
[group('Kali')]
setup-kerbrute:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! distrobox list --root 2>/dev/null | grep -q "{{ kali_box }}"; then
        echo "ERROR: container '{{ kali_box }}' not found." >&2
        echo "Run 'ujust setup-kali' first to provision it." >&2
        exit 1
    fi
    echo "Installing kerbrute inside '{{ kali_box }}' via container-local go install..."
    # kerbrute has no Kali apt package -- upstream only ships GitHub release
    # binaries and `go install`. golang-go is baked into the container's
    # additional_packages specifically to make this work (mirrors
    # libkrb5-dev/python3-dev/pipx for setup-powerview above); "go install ...
    # for the go package inside the container" keeps the host free of a second
    # package manager (no host-side go/brew formula for this).
    #
    # ISOLATED GOPATH/GOBIN: distrobox shares $HOME between host and this
    # rootful container by default. go's default GOPATH ($HOME/go) would land
    # under that shared $HOME -- not a bin-dir collision like pipx's (the host
    # has no go toolchain of its own here), but it would still leak the
    # container's module cache/build artifacts into the host-visible home
    # directory for no reason. We redirect GOPATH/GOBIN to /opt/spinofin/go,
    # which lives in the container's OWN root filesystem -- NOT under $HOME,
    # so it stays invisible to the host (distrobox does not share /opt, only
    # $HOME) -- same isolation approach as PIPX_HOME/PIPX_BIN_DIR above.
    #
    # /usr/local/bin SYMLINK: same reasoning as powerview -- a non-interactive
    # `kali kerbrute ...` call doesn't source ~/.bashrc, so a plain GOBIN PATH
    # addition there would be invisible to it. /usr/local/bin is on the
    # system's default PATH unconditionally, so a single symlink there makes
    # `kerbrute` reachable everywhere INSIDE the container regardless of shell
    # invocation style. The container's /usr/local/bin is part of its own
    # private root filesystem, so this is still container-only.
    # Idempotent: `go install ...@latest`, `ln -sf`, and the export below all
    # handle re-runs cleanly.
    # Ensure go is present before installing. Normally from spinofin-kali.ini;
    # installed on demand here (container-local apt -- does not touch the host
    # or the no-layering policy) so this recipe doesn't fail with "go: command
    # not found" if the container drifted -- this is the "verify installation
    # in the script" step, not just a declared package.
    distrobox enter --root {{ kali_box }} -- bash -lc '
        set -euo pipefail
        if ! command -v go >/dev/null 2>&1; then
            echo "Installing missing container package: golang-go"
            sudo apt-get update -qq
            sudo apt-get install -y golang-go
        fi
    '
    distrobox enter --root {{ kali_box }} -- bash -lc '
        set -euo pipefail
        export GOPATH="/opt/spinofin/go"
        export GOBIN="/opt/spinofin/go/bin"
        sudo mkdir -p "$GOPATH" "$GOBIN"
        sudo chown -R "$(id -u):$(id -g)" "$GOPATH"
        go install github.com/ropnop/kerbrute@latest
        sudo ln -sf "$GOBIN/kerbrute" /usr/local/bin/kerbrute
        # Export the /usr/local/bin symlink (not the GOBIN target directly)
        # to the host, same rootful distrobox-export path as export-impacket,
        # the setup-metasploit exports, and setup-powerview. Only possible
        # failure here is a re-export of an identical wrapper, hence || true.
        distrobox-export --bin /usr/local/bin/kerbrute --export-path "$HOME/.local/bin" >/dev/null 2>&1 || true
    '
    echo ""
    echo "Done. kerbrute is now on PATH everywhere inside the container, AND"
    echo "exported straight to your host shell:"
    echo "  kerbrute --help        # from your host shell directly"
    echo "  kali kerbrute --help   # equivalent, using the kali alias"
    echo "  ujust enter-kali       # then: kerbrute --help"

# Remove the Kali toolbox container entirely
[group('Kali')]
remove-kali:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Removing '{{ kali_box }}' ..."
    distrobox rm --root --force {{ kali_box }} || true
    echo "Removed."

# Set the login shell inside the Kali toolbox container (bash, zsh, or fish)
[group('Kali')]
toggle-kali-shell:
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
    echo "Which shell should '{{ kali_box }}' launch when you enter it?"
    echo "  1. bash (default)"
    echo "  2. zsh"
    echo "  3. fish"
    read -rp "Enter a number [1-3]: " choice
    case "${choice}" in
        1) shell_name="bash" ;;
        2) shell_name="zsh" ;;
        3) shell_name="fish" ;;
        *)
            echo "ERROR: invalid choice '${choice}' -- expected 1, 2, or 3." >&2
            exit 1
            ;;
    esac
    # Everything below runs INSIDE the rootful container. apt here is container-
    # local -- it does not touch the host or the no-layering policy (same as the
    # container side of `ujust toggle-nmap`). We install BEFORE switching on
    # purpose: `distrobox enter` launches the container user's login shell, so
    # pointing it at a shell that isn't installed would break `ujust enter-kali`
    # itself (distrobox errors with "executable file not found"). The shell name
    # is injected as an env var (validated to one of bash/zsh/fish above) to keep
    # the in-container script free of nested quoting.
    distrobox enter --root --additional-flags "--env SPINOFIN_SHELL=${shell_name}" {{ kali_box }} -- bash -lc '
        set -euo pipefail
        target_user="$(id -un)"
        if ! command -v "$SPINOFIN_SHELL" >/dev/null 2>&1; then
            echo "Installing $SPINOFIN_SHELL in the container (apt)..."
            sudo apt-get update -qq
            sudo apt-get install -y "$SPINOFIN_SHELL"
        fi
        shell_path="$(command -v "$SPINOFIN_SHELL" 2>/dev/null || true)"
        if [ -z "$shell_path" ] || [ ! -x "$shell_path" ]; then
            echo "ERROR: $SPINOFIN_SHELL did not install cleanly; leaving the shell unchanged." >&2
            exit 1
        fi
        current="$(getent passwd "$target_user" | cut -d: -f7)"
        if [ "$current" = "$shell_path" ]; then
            echo "Container login shell already set to $shell_path."
        else
            sudo usermod -s "$shell_path" "$target_user"
            echo "Set login shell for $target_user to $shell_path."
        fi
    '
    echo ""
    echo "Done. Run 'ujust enter-kali' to land in ${shell_name}."
    echo "NOTE: zsh/fish here are container-local and are NOT declared in"
    echo "custom/distrobox/spinofin-kali.ini, so 'ujust rebuild-kali' recreates the"
    echo "container with its default shell (bash). Re-run 'ujust toggle-kali-shell'"
    echo "after a rebuild if you want a non-default shell back."
