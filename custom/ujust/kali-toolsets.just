# vim: set ft=make :
#########################
### kali-toolsets.just
#########################
## On-demand Kali tool *families* (metapackages) for the shared spinofin-kali
## container. apt runs container-local (never on the host / the bootc image).
## Not added to the manifest's additional_packages, so first-boot assemble stays
## small and users pull only the families they want.
##
## Hardware families (wireless, 802-11, bluetooth, rfid, sdr) are omitted: they
## need host device passthrough a rootful distrobox can't provide, so the
## metapackage alone wouldn't make them work (roadmap known-hard item).

# `kali_box` is defined in kali-container.just (concatenated into the same
# merged justfile) -- redefining it here would make `just` fail with "multiple
# definitions". Recipes below reference it at run time.

# Install one Kali tool family into the container (arg = the kali-tools-<family> suffix)
[group('Kali Toolsets')]
install-kali-toolset family:
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
    meta="kali-tools-{{ family }}"
    echo "Installing ${meta} inside '{{ kali_box }}' (container-local apt)."
    echo "Some families are multi-GB and can take a while on first install."
    # Runs as root INSIDE the container via distrobox's passwordless sudo.
    # DEBIAN_FRONTEND=noninteractive avoids debconf prompts hanging the install
    # (e.g. the wireshark 'allow non-root capture?' question takes its default).
    distrobox enter --root {{ kali_box }} -- sudo bash -lc \
        "apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y ${meta}"
    echo ""
    echo "Done. ${meta} is installed in the container."
    echo "Run its tools via:  distrobox enter --root {{ kali_box }}"

# Reconnaissance & information-gathering tools
[group('Kali Toolsets')]
install-kali-information-gathering: (install-kali-toolset "information-gathering")

# Vulnerability analysis / scanning tools
[group('Kali Toolsets')]
install-kali-vulnerability: (install-kali-toolset "vulnerability")

# Web application assessment tools (large download)
[group('Kali Toolsets')]
install-kali-web: (install-kali-toolset "web")

# Database assessment tools
[group('Kali Toolsets')]
install-kali-database: (install-kali-toolset "database")

# Password attack & cracking tools (large download)
[group('Kali Toolsets')]
install-kali-passwords: (install-kali-toolset "passwords")

# Exploitation tools & frameworks
[group('Kali Toolsets')]
install-kali-exploitation: (install-kali-toolset "exploitation")

# Post-exploitation tools
[group('Kali Toolsets')]
install-kali-post-exploitation: (install-kali-toolset "post-exploitation")

# Reverse engineering tools
[group('Kali Toolsets')]
install-kali-reverse-engineering: (install-kali-toolset "reverse-engineering")

# Network sniffing & spoofing tools
[group('Kali Toolsets')]
install-kali-sniffing-spoofing: (install-kali-toolset "sniffing-spoofing")

# Curated Kali "Top 10" starter set
[group('Kali Toolsets')]
install-kali-top10: (install-kali-toolset "top10")

# List the Kali tool families spinofin exposes (and the apt name each maps to)
[group('Kali Toolsets')]
list-kali-toolsets:
    #!/usr/bin/env bash
    set -euo pipefail
    cat <<'EOF'
    Available Kali tool families (install with: ujust install-kali-<name>):
      information-gathering   -> kali-tools-information-gathering
      vulnerability           -> kali-tools-vulnerability
      web                     -> kali-tools-web                (large)
      database                -> kali-tools-database
      passwords               -> kali-tools-passwords          (large)
      exploitation            -> kali-tools-exploitation
      post-exploitation       -> kali-tools-post-exploitation
      reverse-engineering     -> kali-tools-reverse-engineering
      sniffing-spoofing       -> kali-tools-sniffing-spoofing
      top10                   -> kali-tools-top10

    Install any family directly:  ujust install-kali-toolset <family>

    Hardware families (wireless, 802-11, bluetooth, rfid, sdr) are omitted on
    purpose -- they need host device passthrough (roadmap known-hard item).
    EOF
