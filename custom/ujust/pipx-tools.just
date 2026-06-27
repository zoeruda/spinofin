# vim: set ft=make :
###################
### pipx-tools.just
###################
## Python-only tooling installed at runtime via pipx (Phase 3 host-side bucket).
##
## Tools are DECLARED in custom/pipx/default.pipx, which the build copies into
## the image at /usr/share/spinofin/pipx/. These recipes just read that list --
## the list is the source of truth, not these commands. pipx installs into the
## invoking user's ~/.local (isolated venvs), so this is user-scoped and must
## NOT be run under sudo.

pipx_list := "/usr/share/spinofin/pipx/default.pipx"

# Install all Python apps declared in custom/pipx/default.pipx via pipx
[group('Apps')]
install-pipx-tools:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v pipx >/dev/null 2>&1; then
        echo "pipx not found; trying to install it via Homebrew..."
        if command -v brew >/dev/null 2>&1; then
            brew install pipx
        else
            echo "ERROR: neither pipx nor brew is available." >&2
            echo "Run 'ujust install-default-apps' first (it installs pipx)." >&2
            exit 1
        fi
    fi
    if [ ! -f "{{ pipx_list }}" ]; then
        echo "ERROR: pipx list not found at {{ pipx_list }}" >&2
        exit 1
    fi
    echo "Installing Python apps from {{ pipx_list }} (re-running is safe)..."
    failed=()
    while IFS= read -r line || [ -n "$line" ]; do
        spec="${line#"${line%%[![:space:]]*}"}"
        spec="${spec%"${spec##*[![:space:]]}"}"
        [ -z "$spec" ] && continue
        case "$spec" in \#*) continue ;; esac
        echo "==> pipx install $spec"
        if ! pipx install "$spec"; then
            echo "    FAILED: $spec"
            failed+=("$spec")
        fi
    done <"{{ pipx_list }}"
    if [ "${#failed[@]}" -ne 0 ]; then
        echo ""
        echo "Some installs failed: ${failed[*]}" >&2
        exit 1
    fi
    echo "All pipx tools installed."

# Upgrade every pipx-managed app to its latest version
[group('Apps')]
upgrade-pipx-tools:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v pipx >/dev/null 2>&1; then
        echo "pipx is not installed; nothing to upgrade." >&2
        exit 1
    fi
    pipx upgrade-all

# List Python apps currently installed by pipx
[group('Apps')]
list-pipx-tools:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v pipx >/dev/null 2>&1; then
        echo "pipx is not installed." >&2
        exit 1
    fi
    pipx list
