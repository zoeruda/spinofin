# spinofin: shell aliases for the shared Kali toolbox container.
# Baked into the image (see custom/aliases/README.md) -- no setup step needed.
#
#   kali <cmd>      -- run <cmd> in the spinofin-kali container as YOUR USER
#                       (no args -> interactive shell, same as `ujust enter-kali`)
#   kalisudo <cmd>  -- same, but as ROOT in the container
#   iskali          -- report whether the spinofin-kali container exists
#                       (exit 0 = present, non-zero = not created yet)
#
# Plain functions (not `alias`) so multi-word/quoted arguments forward
# correctly.
#
# EXISTENCE GUARD: if the container does not exist yet, plain `distrobox enter`
# does NOT fail cleanly -- by default it interactively offers to CREATE a new
# container under that same name using the HOST's own default image (Fedora,
# for spinofin), which is not what you want here. So we check first and tell
# you to run `ujust setup-kali` instead of letting that prompt fire.
#
# Uses `return`, never `exit` -- these are FUNCTIONS sourced into your
# interactive shell, not standalone scripts; `exit` here would close your
# whole terminal session.
_spinofin_kali_check() {
    if ! command -v distrobox >/dev/null 2>&1; then
        echo "spinofin: distrobox not found on host." >&2
        return 1
    fi
    if ! distrobox list --root 2>/dev/null | grep -q "spinofin-kali"; then
        echo "spinofin: the 'spinofin-kali' container doesn't exist yet." >&2
        echo "Run 'ujust setup-kali' first, then try again." >&2
        return 1
    fi
}

kali() {
    _spinofin_kali_check || return 1
    if [ "$#" -eq 0 ]; then
        # No args -> full interactive shell, identical to `ujust enter-kali`.
        # Do NOT fall through to the `-- "$@"` form below with an empty command:
        # a trailing `distrobox enter ... --` with nothing after it does not
        # reliably drop you into the container's LOGIN shell -- you can land in a
        # non-login, non-interactive shell where ~/.bashrc is never sourced, so
        # there is no prompt (PS1) and the environment is stripped. Calling
        # `distrobox enter` with no command at all takes distrobox's default
        # path, which execs your shell as a login shell (verified in distrobox:
        # an empty command runs `$SHELL -l`), giving the full prompt + env.
        # --no-workdir enters at the container's $HOME rather than the host cwd
        # (a rootful box maps that under /run/host), and the `|| true` mirrors
        # enter-kali exactly: leaving via `exit`/Ctrl-D carries your LAST
        # command's exit code, which is not a failure of `kali` itself.
        distrobox enter --root --no-workdir spinofin-kali || true
    else
        # With args -> run that command in the container as your user, non-login
        # and non-interactive. ~/.bashrc is NOT sourced on this path, which is
        # why such tools must be reachable without a shell rc -- see the
        # /usr/local/bin symlink note in setup-powerview (kali-container.just).
        distrobox enter --root spinofin-kali -- "$@"
    fi
}

kalisudo() {
    _spinofin_kali_check || return 1
    distrobox enter --root spinofin-kali -- sudo "$@"
}

# iskali -- report whether the shared Kali toolbox container exists, without
# entering it. Uses the same detection as the guard above. Exit 0 if present,
# non-zero if not, so it works in scripts (`iskali && kali nmap ...`) as well
# as interactively. `return`, not `exit`: this is sourced into your shell.
iskali() {
    if ! command -v distrobox >/dev/null 2>&1; then
        echo "spinofin: distrobox not found on host." >&2
        return 2
    fi
    if distrobox list --root 2>/dev/null | grep -q "spinofin-kali"; then
        echo "spinofin-kali: present"
        return 0
    fi
    echo "spinofin-kali: not created yet -- run 'ujust setup-kali'"
    return 1
}
