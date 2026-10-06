# Build Scripts

This directory contains build scripts that execute during the container image build process (`Containerfile`).

## Architecture & No-Layering Policy

> [!IMPORTANT]
> **No Build-Time Package Layering:**
> spinofin strictly forbids package installation via `dnf5`, `dnf`, `yum`, `apt`, or `rpm-ostree` during image builds. Build scripts perform declarative system configuration, asset staging, and service management only. All CLI tools, GUI applications, and penetration testing packages are delivered at runtime via Homebrew (`custom/brew/*.Brewfile`), pipx (`custom/pipx/*.pipx`), Flatpak (`custom/flatpaks/*.preinstall`), and Kali containers (`spinofin-kali` and `kalicli`).
>
> Any PR adding package-manager install commands to `build/*.sh` is automatically rejected by `.github/workflows/no-layering-check.yml`.

## Execution Order

The `Containerfile` runs scripts in explicit order via bind mounts (`/ctx`):

1. **`00-image-info.sh`** — Sets up image identity, versioning, and `/etc/os-release` configuration.
2. **`10-build.sh`** — Base system modifications, systemd service presets, and kernel argument validation.
3. **`15-branding.sh`** — Installs distribution branding, wallpapers, and application icons.
4. **`16-initramfs.sh`** — Regenerates initramfs with custom drivers/configurations.
5. **`17-aliases.sh`** — Copies system profile scripts (`/etc/profile.d/` and `/etc/fish/conf.d/`) for container aliases.
6. **`18-sudo-prompt.sh`** — Configures default sudo prompt behavior.
7. **`clean-stage.sh`** — Purges caches, temporary files, and build context remnants.

## Helper Scripts

- **`copr-helpers.sh`** — Template library for isolated COPR handling (retained for template compatibility; not used in spinofin due to the no-layering policy).

## Best Practices

- **Strict Error Handling**: Always include `set -euo pipefail` at the top of every script.
- **Idempotent Operations**: Ensure operations succeed even if run repeatedly.
- **Clean Context**: Clean up any temporary files created in `/tmp` before completing the stage.
- **ShellCheck Compliance**: Run `just lint` (`shellcheck`) to ensure all scripts adhere to static analysis standards.
