# shellcheck shell=bash
# spinofin: shell alias for the rootless `kalicli` podman container.
# Baked into the image (see custom/aliases/README.md) -- no setup step needed.
#
#   kalicli <cmd>   -- run <cmd> inside the kalicli container
#                      (no args -> interactive shell)
#   iskalicli       -- is kalicli built/running? (0 present / 1 not set up / 2 no podman)
#
# There is deliberately NO `kaliclisudo` counterpart, unlike `kali`/`kalisudo`.
# kalicli is rootless: podman maps container UID 0 to your host UID, so you are
# ALREADY root inside the container, and that root has no authority on the host.
#
# Unlike `kali`, this does NOT use distrobox: no /run/host, no $HOME mount. The
# only shared paths are ~/spinofin/work (at /work) and staged wordlists (at /wordlists, ro).
# kalicli is a systemd-managed Quadlet service (spinofin-kalicli.service), started on demand here.
#
# Plain functions (not `alias`) so multi-word/quoted arguments forward
# correctly. Uses `return`, never `exit` -- these are sourced into the
# interactive shell, so `exit` would close the whole terminal.

_spinofin_kalicli_check() {
    if ! command -v podman >/dev/null 2>&1; then
        echo "spinofin: podman not found on host." >&2
        return 1
    fi
    # "Set up" means the local image has been built. The Quadlet unit ships in
    # the image for everyone, so its presence alone doesn't mean setup ran.
    if ! podman image exists localhost/spinofin-kalicli:latest 2>/dev/null; then
        echo "spinofin: the 'kalicli' image isn't built yet." >&2
        echo "Run 'ujust setup-kalicli' first, then try again." >&2
        return 1
    fi
    # Start on demand (e.g. after a reboot -- there is no auto-start).
    if ! systemctl --user is-active --quiet spinofin-kalicli 2>/dev/null; then
        systemctl --user start spinofin-kalicli >/dev/null 2>&1 || {
            echo "spinofin: failed to start the 'kalicli' service." >&2
            echo "Check 'systemctl --user status spinofin-kalicli'." >&2
            return 1
        }
    fi
}

kalicli() {
    _spinofin_kalicli_check || return 1

    # Allocate a TTY only when both stdin and stdout are real terminals, so redirected/piped output
    # or piped input (e.g. cat targets.txt | kalicli tool) does not fail with "input device is not a TTY".
    _kc_flags=("-i")
    if [ -t 0 ] && [ -t 1 ]; then
        _kc_flags+=("-t")
    fi

    if [ "$#" -eq 0 ]; then
        podman exec "${_kc_flags[@]}" spinofin-kalicli /bin/bash -l
    else
        podman exec "${_kc_flags[@]}" spinofin-kalicli "$@"
    fi
    unset _kc_flags
}

# iskalicli -- presence check. Exit-code contract mirrors `iskali`:
#   0 present, 1 not set up, 2 podman missing.
iskalicli() {
    if ! command -v podman >/dev/null 2>&1; then
        echo "spinofin: podman not found on host." >&2
        return 2
    fi
    if podman image exists localhost/spinofin-kalicli:latest 2>/dev/null; then
        if systemctl --user is-active --quiet spinofin-kalicli 2>/dev/null; then
            echo "kalicli: present (running)"
        else
            echo "kalicli: present (stopped -- 'kalicli' will start it on demand)"
        fi
        return 0
    fi
    echo "kalicli: not set up yet -- run 'ujust setup-kalicli'"
    return 1
}
