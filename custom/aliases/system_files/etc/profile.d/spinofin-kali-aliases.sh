# spinofin: shell aliases for the shared Kali toolbox container.
# Baked into the image (see custom/aliases/README.md) -- no setup step needed.
#
#   kali <cmd>      -- run <cmd> in the spinofin-kali container as YOUR USER
#                       (no args -> interactive shell, same as `ujust enter-kali`)
#   kalisudo <cmd>  -- same, but as ROOT in the container (needed for raw
#                       sockets / low ports -- see the impacket privilege
#                       caveat in the README)
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
    distrobox enter --root spinofin-kali -- "$@"
}

kalisudo() {
    _spinofin_kali_check || return 1
    distrobox enter --root spinofin-kali -- sudo "$@"
}
