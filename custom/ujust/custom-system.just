# vim: set ft=make :
#######################
### custom-system.just
#######################
## Example system configuration commands
## These are simplified examples adapted from Bluefin

# Run a system benchmark (requires stress-ng from Homebrew)
[group('System')]
benchmark:
    #!/usr/bin/env bash
    source /usr/lib/ujust/ujust.sh
    if ! type -P "stress-ng" &>/dev/null ; then
        echo "stress-ng is not installed."
        if command -v brew &>/dev/null; then
            if gum confirm "Install stress-ng via Homebrew?" ; then
                brew install stress-ng
                brew link stress-ng
            else
                exit 0
            fi
        else
            echo "Please install stress-ng to run benchmarks."
            exit 1
        fi
    fi
    echo 'Running a 1 minute benchmark...'
    pushd $(mktemp -d) > /dev/null
    stress-ng --matrix 0 -t 1m --times
    popd > /dev/null

# Configure docker and libvirt groups for development
[group('System')]
configure-dev-groups:
    #!/usr/bin/pkexec bash
    CURRENT_USER="{{ `id -un` }}"
    echo "Adding $CURRENT_USER to docker and libvirt groups..."

    # Ensure groups exist in /etc/group
    for group in docker libvirt; do
        if ! grep -q "^$group:" /etc/group; then
            echo "Adding $group to /etc/group"
            grep "^$group:" /usr/lib/group | tee -a /etc/group > /dev/null
        fi
        usermod -aG $group $CURRENT_USER
    done

    echo "Groups configured. Log out and back in for changes to take effect."

# Example toggle command with user choice
[group('System')]
toggle-example-feature:
    #!/usr/bin/bash
    source /usr/lib/ujust/ujust.sh
    echo "This is an example toggle command."
    echo "Current status: [check your status here]"
    OPTION=$(Choose "Enable" "Disable" "Cancel")
    case "$OPTION" in
        "Enable")
            echo "Enabling feature..."
            # Add your enable logic here
            ;;
        "Disable")
            echo "Disabling feature..."
            # Add your disable logic here
            ;;
        "Cancel")
            echo "No changes made."
            ;;
    esac

# Clean up container images and volumes
[group('Maintenance')]
clean-containers:
    #!/usr/bin/bash
    echo "Cleaning up Podman containers, images, and volumes..."
    podman system prune -af
    podman volume prune -f
    echo "Cleanup complete!"

# Update system and reboot if needed
[group('Maintenance')]
update-and-reboot:
    #!/usr/bin/bash
    source /usr/lib/ujust/ujust.sh
    echo "Updating system..."
    sudo bootc upgrade
    if gum confirm "Reboot now to apply updates?"; then
        systemctl reboot
    else
        echo "Reboot later to apply updates."
    fi

# Set the shell new terminals launch on the host (bash, zsh, or fish)
[group('System')]
toggle-shell:
    #!/usr/bin/env bash
    set -euo pipefail
    # bash, zsh, and fish all ship on the Bluefin base already, so "install" is
    # normally a no-op here. If a shell is genuinely missing (e.g. a future
    # Track-B GNOME OS base that doesn't ship it), we fall back to brew -- the
    # same user-scoped, host-pristine path the rest of spinofin uses. We never
    # layer a shell onto the host with rpm-ostree.
    #
    # "Switch to it" deliberately does NOT change your login shell. Bluefin ships
    # no chsh, editing /etc/passwd doesn't change how the terminal launches, and
    # pointing a login shell at a brew shell is a known way to lose brew's PATH.
    # The supported switch on Bluefin is per-terminal: we set the default Ptyxis
    # profile's custom command. (The container recipe, toggle-kali-shell, DOES
    # change the real login shell -- that's correct there, wrong here.)
    echo "Which shell should new terminals launch?"
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

    # --- Resolve (or, only if missing, brew-install) the shell binary ---
    shell_path="$(command -v "${shell_name}" 2>/dev/null || true)"
    if [ -z "${shell_path}" ] && [ -x "/usr/bin/${shell_name}" ]; then
        shell_path="/usr/bin/${shell_name}"
    fi
    if [ -z "${shell_path}" ]; then
        echo "${shell_name} not found on host."
        if command -v brew >/dev/null 2>&1; then
            echo "Installing ${shell_name} via Homebrew (user-scoped, not layered)..."
            brew install "${shell_name}"
            shell_path="$(command -v "${shell_name}" 2>/dev/null || true)"
        else
            echo "ERROR: ${shell_name} is missing and brew isn't available." >&2
            echo "Run 'ujust install-default-apps' (or install Homebrew), then retry." >&2
            exit 1
        fi
    fi
    if [ -z "${shell_path}" ] || [ ! -x "${shell_path}" ]; then
        echo "ERROR: could not resolve an executable path for ${shell_name}." >&2
        exit 1
    fi
    echo "Using ${shell_name} at ${shell_path}"

    # --- Point the default Ptyxis profile at it (user-scoped dconf) ---
    # Do NOT run this recipe under pkexec/sudo, or the setting lands in root's
    # dconf instead of yours.
    if ! command -v gsettings >/dev/null 2>&1; then
        echo ""
        echo "NOTE: gsettings not found -- set your terminal profile's custom"
        echo "command to '${shell_path}' by hand."
        exit 0
    fi
    prof="$(gsettings get org.gnome.Ptyxis default-profile-uuid 2>/dev/null | tr -d "\"'" || true)"
    prof_path="org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/${prof}/"
    if [ -n "${prof}" ] && gsettings list-keys "${prof_path}" 2>/dev/null | grep -qx "custom-command"; then
        if [ "${shell_name}" = "bash" ]; then
            # bash is the profile's default login shell; clear the override.
            gsettings set "${prof_path}" use-custom-command false
            echo "Reset the default Ptyxis profile to its login shell (bash)."
        else
            gsettings set "${prof_path}" custom-command "${shell_path}"
            gsettings set "${prof_path}" use-custom-command true
            echo "Set the default Ptyxis profile to launch ${shell_path}."
        fi
        echo ""
        echo "Open a NEW terminal window or tab to get ${shell_name}."
        echo "(This session keeps its shell; run 'exec ${shell_name}' now if you want it here.)"
    else
        echo ""
        echo "NOTE: no Ptyxis profile found to update (different terminal emulator?)."
        echo "Set your terminal profile's custom command to '${shell_path}' by hand."
    fi
