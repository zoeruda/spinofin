# vim: set ft=make :
###########################
### kalicli-container.just
###########################
## The `kalicli` container -- a ROOTLESS, declaratively-built podman box for
## CLI tools.
##
## FULLY DECLARATIVE: kalicli is defined entirely by two files that ship in the
## spinofin image, with no imperative package steps:
##   - custom/quadlet/Containerfile     -- its tools (built into an immutable
##                                          localhost/spinofin-kalicli image)
##   - custom/quadlet/spinofin-kalicli.container -- its runtime (a podman Quadlet,
##                                          installed as a user systemd unit)
## These recipes build that image and drive the systemd unit. The durable way
## to change the toolset is to edit the Containerfile and `rebuild-kalicli`,
## which reconciles the container back to the declared set. (`upgrade-kalicli`
## does an in-place apt upgrade that keeps ad-hoc installs, so the running
## container can drift until the next rebuild.) The image itself stays an
## immutable, reproducible artifact -- unlike the spinofin-kali distrobox, whose
## tools are apt-installed into a mutable container at assemble time.)
##
## WHY IT EXISTS (vs spinofin-kali): spinofin-kali is a ROOTFUL distrobox that
## mounts the host's / at /run/host plus your $HOME -- container-root there is
## real host root. kalicli is the opposite trade: rootless (podman maps
## container UID 0 to your host UID, so "root" inside has no host authority),
## no /run/host, no $HOME mount, no exported binaries. The ONLY shared path is
## ~/spinofin/work, mounted at /work. That is why there is no `kaliclisudo`:
## you are already root inside and it buys no privilege. Prefer kalicli for any
## tool that does not need root or raw sockets.
##
## LIMITS: rootless networking (pasta/slirp4netns) has no raw sockets (no nmap
## SYN scans, no tcpdump) and slower bulk transfers; anything in ~/spinofin/work
## IS reachable by the container; container isolation is weaker than a VM.

kalicli_box := "spinofin-kalicli"
kalicli_image := "localhost/spinofin-kalicli:latest"
kalicli_containerfile := "/usr/share/spinofin/quadlet/Containerfile"
kalicli_workdir := "spinofin/work"

# Build the rootless kalicli image from its Containerfile and start it
[group('Kali CLI')]
setup-kalicli:
    #!/usr/bin/env bash
    set -euo pipefail

    if ! command -v podman >/dev/null 2>&1; then
        echo "podman not found on host. It ships with Bluefin -- something is wrong." >&2
        exit 1
    fi
    if [ ! -r "{{ kalicli_containerfile }}" ]; then
        echo "Missing {{ kalicli_containerfile }} -- it should have been baked" >&2
        echo "into the image by build/10-build.sh." >&2
        exit 1
    fi
    if ! systemctl --user show-environment >/dev/null 2>&1; then
        echo "No user systemd session available; can't manage the kalicli unit." >&2
        echo "Log in to a normal desktop session and try again." >&2
        exit 1
    fi

    # Idempotent: if the image is already built and the unit is running, stop.
    if podman image exists "{{ kalicli_image }}" \
        && systemctl --user is-active --quiet "{{ kalicli_box }}"; then
        echo "'{{ kalicli_box }}' is already set up and running."
        echo ""
        echo "  kalicli                 # shell inside it"
        echo "  ujust upgrade-kalicli   # apt update + full-upgrade in place"
        exit 0
    fi

    # Prepare shared host paths: work directory and staged wordlists mount point.
    mkdir -p "${HOME}/{{ kalicli_workdir }}"
    mkdir -m 0700 -p "${HOME}/.local/share/spinofin/wordlists"
    chmod 0700 "${HOME}/.local/share/spinofin/wordlists"

    echo "Building '{{ kalicli_image }}' from its Containerfile (pulls kali-rolling"
    echo "and installs the declared tools; takes a while on first run) ..."
    podman build --pull=newer -t "{{ kalicli_image }}" \
        -f "{{ kalicli_containerfile }}" \
        "$(dirname "{{ kalicli_containerfile }}")"

    # The Quadlet unit ships in the image (/etc/containers/systemd/users/); a
    # daemon-reload makes sure it is generated in this session before we start.
    systemctl --user daemon-reload
    # Clear any leftover named container from a previous run, then start.
    podman rm -f "{{ kalicli_box }}" >/dev/null 2>&1 || true
    systemctl --user start "{{ kalicli_box }}"

    echo ""
    echo "'{{ kalicli_box }}' is ready."
    echo ""
    echo "  kalicli                 # interactive shell in the container"
    echo "  kalicli sqlmap --help   # run a single command"
    echo ""
    echo "Files: put inputs in ~/{{ kalicli_workdir }} (visible as /work inside);"
    echo "wordlists are mounted read-only at /wordlists (run 'ujust link-wordlists')."
    echo "Prefer kalicli over the spinofin-kali box for anything that does not need"
    echo "root or raw sockets."

# Enter an interactive shell in the kalicli container (same as the `kalicli` alias)
[group('Kali CLI')]
enter-kalicli:
    #!/usr/bin/env bash
    set -euo pipefail
    # Nearly identical to the `kalicli` alias with no arguments, and kept for
    # parity with `enter-kali` -- plus it works when the alias isn't available
    # (a non-interactive shell, or before /etc/profile.d is sourced). The alias
    # is the richer path (it forwards `kalicli <cmd>`); this is just the shell.
    if ! command -v podman >/dev/null 2>&1; then
        echo "podman not found on host." >&2
        exit 1
    fi
    if ! podman image exists "{{ kalicli_image }}"; then
        echo "'{{ kalicli_box }}' isn't set up yet. Run 'ujust setup-kalicli' first." >&2
        exit 1
    fi
    # Start on demand (no auto-start; may be stopped after a reboot).
    if ! systemctl --user is-active --quiet "{{ kalicli_box }}" 2>/dev/null; then
        systemctl --user start "{{ kalicli_box }}"
    fi
    # Interactive shell in the rootless container. You are root inside, but that
    # root maps to your own host UID -- no password, and no host authority (so
    # no sudo-password prompt like enter-kali has). Leaving via exit/Ctrl-D
    # inherits the last command's status and is not a recipe failure, so the
    # exit code is discarded, matching enter-kali.
    podman exec -it "{{ kalicli_box }}" /bin/sh -c 's="$(getent passwd "$(id -un)" | cut -d: -f7 2>/dev/null || true)"; [ -n "$s" ] && [ -x "$s" ] || s=/bin/bash; exec "$s" -l' || true

# Upgrade packages inside the kalicli container in place (keeps what you added)
[group('Kali CLI')]
upgrade-kalicli:
    #!/usr/bin/env bash
    set -euo pipefail

    # In-place apt upgrade of the RUNNING container. This keeps anything you
    # installed on top of the declared image (it writes to the container's own
    # layer, not the image), so the container may drift from the Containerfile
    # -- that's the intended trade-off for a quick, non-destructive update.
    # To instead discard in-container changes and reconcile back to the declared
    # toolset (and pick up a newer kali-rolling base), use 'ujust rebuild-kalicli'.
    if ! command -v podman >/dev/null 2>&1; then
        echo "podman not found on host." >&2
        exit 1
    fi
    if ! podman image exists "{{ kalicli_image }}"; then
        echo "'{{ kalicli_box }}' isn't set up yet. Run 'ujust setup-kalicli' first." >&2
        exit 1
    fi
    # apt runs inside the container, so it has to be running; start on demand
    # (there is no auto-start, so it may be stopped after a reboot).
    if ! systemctl --user is-active --quiet "{{ kalicli_box }}" 2>/dev/null; then
        systemctl --user start "{{ kalicli_box }}"
    fi

    echo "Upgrading packages inside '{{ kalicli_box }}' in place ..."
    podman exec "{{ kalicli_box }}" env DEBIAN_FRONTEND=noninteractive apt-get update
    podman exec "{{ kalicli_box }}" env DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y
    podman exec "{{ kalicli_box }}" env DEBIAN_FRONTEND=noninteractive apt-get autoremove -y
    echo "Done. Upgraded in place; anything you installed on top was kept."
    echo "(Use 'ujust rebuild-kalicli' to rebuild from the Containerfile instead.)"

# Destroy the kalicli image + container and rebuild from the Containerfile (prompts)
[group('Kali CLI')]
rebuild-kalicli:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "This recreates '{{ kalicli_box }}' from scratch: it removes the built"
    echo "image and the container and rebuilds from the Containerfile, reconciling"
    echo "back to the declared toolset. Anything you apt-installed or changed inside"
    echo "the container -- including via 'ujust upgrade-kalicli' -- is lost;"
    echo "~/{{ kalicli_workdir }} is NOT touched."
    echo ""
    read -rp "Rebuild '{{ kalicli_box }}' from scratch? [y/N] " reply
    case "${reply}" in
        [yY]|[yY][eE][sS]) ;;
        *) echo "Aborted."; exit 0 ;;
    esac

    # Drop the container (discards its in-place upgrade layer) and the image,
    # then let setup-kalicli do the clean build + start. setup-kalicli only
    # no-ops when the image already exists -- which it won't, after the rmi.
    systemctl --user stop "{{ kalicli_box }}" 2>/dev/null || true
    podman rm -f "{{ kalicli_box }}" >/dev/null 2>&1 || true
    podman rmi -f "{{ kalicli_image }}" >/dev/null 2>&1 || true
    ujust setup-kalicli

# Show whether kalicli is built, running, and where its one shared path is
[group('Kali CLI')]
kalicli-status:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "spinofin kalicli status"
    echo "======================="
    if ! command -v podman >/dev/null 2>&1; then
        echo "podman:  NOT FOUND on host -- something is wrong, it ships with Bluefin."
        exit 1
    fi

    img_present=no
    podman image exists "{{ kalicli_image }}" && img_present=yes
    unit_state="$(systemctl --user is-active "{{ kalicli_box }}" 2>/dev/null || true)"
    workdir="${HOME}/{{ kalicli_workdir }}"

    if [ "${img_present}" = no ] && [ "${unit_state}" != active ]; then
        echo "Container ({{ kalicli_box }}):  NOT SET UP"
        echo ""
        echo "Run 'ujust setup-kalicli' to build and start it."
        exit 0
    fi

    echo "Image ({{ kalicli_image }}):  $([ "${img_present}" = yes ] && echo present || echo 'MISSING -- run ujust rebuild-kalicli')"
    if [ "${img_present}" = yes ]; then
        echo "  built: $(podman image inspect -f '{{{{.Created}}}}' "{{ kalicli_image }}" 2>/dev/null | cut -c1-19)"
        echo "  base:  $(podman image inspect -f '{{{{index .RepoTags 0}}}}' "{{ kalicli_image }}" 2>/dev/null || true)"
    fi
    echo "Service (spinofin-kalicli.service):  ${unit_state:-inactive}"
    if [ "${unit_state}" = "active" ]; then
        login_shell="$(podman exec "{{ kalicli_box }}" sh -c 'basename "$(getent passwd root | cut -d: -f7 2>/dev/null || true)"' 2>/dev/null || true)"
        echo "Login shell:  ${login_shell:-bash} (change with: ujust toggle-kalicli-shell)"
    fi
    wordlists_dir="${HOME}/.local/share/spinofin/wordlists"
    echo "Shared dir:  ${workdir}  ->  /work  $([ -d "${workdir}" ] && echo '(exists)' || echo '(will be created on setup)')"
    echo "Wordlists:   ${wordlists_dir}  ->  /wordlists (ro)  $([ -d "${wordlists_dir}" ] && [ -n "$(ls -A "${wordlists_dir}" 2>/dev/null)" ] && echo '(staged)' || echo '(empty -- run ujust link-wordlists)')"
    echo ""
    echo "Tools are baked into the image from custom/quadlet/Containerfile."
    echo "To change them, edit that file and run 'ujust rebuild-kalicli'."

# Remove the kalicli container and built image (leaves ~/spinofin/work untouched)
[group('Kali CLI')]
remove-kalicli:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Removing '{{ kalicli_box }}' ..."
    systemctl --user stop "{{ kalicli_box }}" 2>/dev/null || true
    podman rm -f "{{ kalicli_box }}" >/dev/null 2>&1 || true
    podman rmi -f "{{ kalicli_image }}" >/dev/null 2>&1 || true
    echo "Removed the container and built image. Your files in ~/{{ kalicli_workdir }}"
    echo "were left alone. The unit definition ships with the image, so it stays"
    echo "(inert without the image); 'ujust setup-kalicli' brings it back."

# Set the login shell inside the kalicli container (bash/zsh/fish; scriptable: `ujust toggle-kalicli-shell zsh`)
[group('Kali CLI')]
toggle-kalicli-shell shell="":
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v podman >/dev/null 2>&1; then
        echo "podman not found on host." >&2
        exit 1
    fi
    if ! podman image exists "{{ kalicli_image }}"; then
        echo "'{{ kalicli_box }}' isn't set up yet. Run 'ujust setup-kalicli' first." >&2
        exit 1
    fi
    # Start on demand (no auto-start; may be stopped after a reboot).
    if ! systemctl --user is-active --quiet "{{ kalicli_box }}" 2>/dev/null; then
        systemctl --user start "{{ kalicli_box }}"
    fi
    # INPUT: an optional argument (`ujust toggle-kalicli-shell zsh`) makes this
    # non-interactive for scripted provisioning; validated against the same
    # bash/zsh/fish allowlist as the menu. With no argument we fall back to the
    # interactive prompt, so the bare `ujust toggle-kalicli-shell` UX is unchanged.
    requested="{{ shell }}"
    if [ -n "${requested}" ]; then
        case "${requested}" in
            bash | zsh | fish) shell_name="${requested}" ;;
            *)
                echo "ERROR: invalid shell '${requested}' -- expected bash, zsh, or fish." >&2
                exit 1
                ;;
        esac
    else
        echo "Which shell should '{{ kalicli_box }}' launch when you enter it?"
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
    fi
    # Everything below runs INSIDE the rootless container via podman exec.
    # Container UID 0 maps to your host UID, so commands run as root inside
    # without sudo. apt here is container-local -- it does not touch the host
    # or the no-layering policy. We install BEFORE switching on purpose:
    # entering the container launches the login shell, so pointing it at a shell
    # that isn't installed would break entry. The shell name is injected as an
    # env var (validated to one of bash/zsh/fish above) to keep the in-container
    # script free of nested quoting.
    podman exec --env "SPINOFIN_SHELL=${shell_name}" "{{ kalicli_box }}" bash -lc '
        set -euo pipefail
        target_user="$(id -un)"
        if ! command -v "$SPINOFIN_SHELL" >/dev/null 2>&1; then
            echo "Installing $SPINOFIN_SHELL in the container (apt)..."
            DEBIAN_FRONTEND=noninteractive apt-get update -qq
            DEBIAN_FRONTEND=noninteractive apt-get install -y "$SPINOFIN_SHELL"
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
            usermod -s "$shell_path" "$target_user"
            echo "Set login shell for $target_user to $shell_path."
        fi
    '
    echo ""
    echo "Done. Run 'ujust enter-kalicli' or 'kalicli' to land in ${shell_name}."
    echo "NOTE: zsh/fish here are container-local and are NOT declared in"
    echo "custom/quadlet/Containerfile, so 'ujust rebuild-kalicli' recreates the"
    echo "container with its default shell (bash). Re-run 'ujust toggle-kalicli-shell'"
    echo "after a rebuild if you want a non-default shell back."
