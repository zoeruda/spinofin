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
# correctly. Errors harmlessly if the container hasn't been created yet
# (run `ujust setup-kali` first) -- distrobox prints its own clear message.
kali() {
    distrobox enter --root spinofin-kali -- "$@"
}

kalisudo() {
    distrobox enter --root spinofin-kali -- sudo "$@"
}
