# vim: set ft=make :
####################
### custom-apps.just
####################
## Example application installation commands
## See .agents/skills/finpilot-custom.md for runtime layer guidance
## See .agents/skills/finpilot-examples.md for activation patterns

# Install default applications via Homebrew
[group('Apps')]
install-default-apps:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Installing default applications via Homebrew..."
    brew bundle --file /usr/share/ublue-os/homebrew/default.Brewfile
    # `brew bundle` only installs a Brewfile's own top-level formulas -- for one
    # already installed (e.g. rustscan), it does NOT re-verify that formula's
    # OWN dependencies are still present. So if a dependency was separately
    # removed later (e.g. a manual `brew uninstall --ignore-dependencies nmap`
    # while rustscan stays installed), a plain re-run of this recipe silently
    # does nothing about it. `brew missing` is
    # the purpose-built check for exactly this: it lists every installed
    # formula that's missing one of its own dependencies. Reinstall those
    # formulas (not just the bare missing package) so Homebrew's normal
    # install-time dependency resolution runs again and pulls it back in.
    mapfile -t broken < <(brew missing | cut -d: -f1 | sort -u)
    if [ "${#broken[@]}" -gt 0 ]; then
        echo "Repairing formulas with missing dependencies: ${broken[*]}"
        brew reinstall "${broken[@]}"
    fi

# Install development tools via Homebrew
[group('Apps')]
install-dev-tools:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Installing development tools via Homebrew..."
    brew bundle --file /usr/share/ublue-os/homebrew/development.Brewfile

# Install fonts via Homebrew
[group('Apps')]
install-fonts:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Installing fonts via Homebrew..."
    brew bundle --file /usr/share/ublue-os/homebrew/fonts.Brewfile

# Install all Brewfiles at once
[group('Apps')]
install-all-brew:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Installing all applications from Brewfiles..."
    brew bundle --file /usr/share/ublue-os/homebrew/default.Brewfile
    brew bundle --file /usr/share/ublue-os/homebrew/development.Brewfile
    brew bundle --file /usr/share/ublue-os/homebrew/fonts.Brewfile

# Install a Flatpak application from Flathub
[group('Apps')]
install-flatpak APP_ID:
    #!/usr/bin/bash
    echo "Installing {{ APP_ID }} from Flathub..."
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    flatpak install -y flathub {{ APP_ID }}
