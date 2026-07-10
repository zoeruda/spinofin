# spinofin branding assets

Drop-in slots for spinofin's OS-identity branding (boot splash, login, panel
logo, installer) — replacing the Bluefin/ublue logos the base image ships.

This is **OS-identity** branding only, not a desktop reskin. Wallpapers
(including the Bluefin dinosaurs), the GTK/icon theme, and accent colors stay
Bluefin by project decision.

## No-layering posture

Nothing here installs a package. Every surface is either a **file overwrite**
of an asset the base image already ships, or a **dconf default** pointing at
an asset we ship — so the no-layering CI guard doesn't fire, and there's
nothing to unwind at the eventual Track-B (GNOME OS bootc) migration.

## Layout

```
custom/branding/
├── system_files/    # copied verbatim into / by build/15-branding.sh
│   └── usr/share/...
├── deferred/        # NOT wired -- installer art; mechanism unconfirmed (see below)
└── optional/        # NOT wired -- fastfetch/about art we're keeping stock Bluefin for now
```

## Source-of-truth assets

Author two masters, then derive every raster/variant from them:

1. **Wordmark** (horizontal lockup) → splash, login, installer, About.
2. **Symbolic glyph** (square, single-color) → panel icon, About icon.

## Slots (`system_files/`)

### 1. Boot splash — Plymouth

- Files: `system_files/usr/share/plymouth/themes/spinner/watermark.png` and `.../silverblue-watermark.png` — filenames must stay exact (overwrite).
- Format: PNG-32, transparent, **light/white** art (boot bg is dark). Stock size 149×43; produce at ~300×88 (Plymouth doesn't scale, so bigger = crisper on HiDPI).
- The `spinner` theme draws this; `bgrt` inherits the same image dir, so one file covers both. Replace both PNGs.

### 2. Login screen — GDM logo

- File: `system_files/usr/share/pixmaps/spinofin-gdm-logo.png` (net-new; the dconf key points at it).
- Format: PNG-32 transparent, light monochrome, ~150×61 (SVG also fine).
- Mechanism: `org.gnome.login-screen logo` in the `gdm` dconf db. Bluefin sets no greeter logo today, so this is an addition, not a replacement.

### 3. Panel logo — Logo Menu

- File: `system_files/usr/share/icons/hicolor/scalable/actions/spinofin-logo-symbolic.svg` (optional colored variant: `.../spinofin-logo.svg`).
- Format: square viewBox, single path, `fill="currentColor"` (let GNOME recolor light/dark — don't hardcode). Renders at ~16–25px on the top bar, so the silhouette needs to read at that size.
- Mechanism: **Logo Menu** (`logomenu@aryan_k`) is the extension Bluefin ships enabled by default, so it's the primary target — `use-custom-icon`, `custom-icon-path`, and `symbolic-icon` are set in the distro dconf db, pointing at our SVG. Logo Menu also bundles its own `kali-linux-logo-symbolic.svg` at index 9 of its preset gallery, if the Kali dragon is ever wanted there instead.
- If a user separately installs and enables **Custom Command Menu** (`custom-command-list@storageb.github.com`, not shipped/enabled by default), its `menuicon-setting` key is pre-set to `'spinofin-logo-symbolic'` too, so it shows the same mark out of the box rather than its own upstream default.
- Neither of these are locked — see "User-Customizable Panel Logo" below.

### User-Customizable Panel Logo

The panel logo isn't locked: users change it anytime via `gnome-extensions
prefs logomenu@aryan_k` (or Custom Command Menu's prefs, if installed), and
it survives every subsequent `bootc upgrade`.

A plain `distro.d` dconf default only applies when the account has no
explicit value of its own, which doesn't reliably cover spinofin's main
delivery path (rebasing an existing Bluefin install, where Logo Menu already
has an explicit enabled/default value). To handle that, `build/15-branding.sh`
ships `etc/xdg/autostart/spinofin-branding-migrate-user-logo.desktop`, a
standard XDG autostart entry (no custom systemd unit, no `systemctl enable`
step) that `gnome-session` runs on first graphical login. It calls
`usr/libexec/spinofin/branding-migrate-user-logo`, which writes spinofin's
icon into that account's own dconf db via `gsettings set` — exactly as if
the user had picked it themselves — then stamps
`~/.local/state/spinofin/branding-migrated` so it never runs again. From
then on the value is an ordinary, unlocked, user-owned dconf entry: prefs
UIs work normally, and whatever the user sets next persists across every
later `bootc upgrade` (per-user dconf lives under `/home`, untouched by
ostree updates).

A user who'd already hand-picked a custom panel icon under
Bluefin *before* rebasing will have that choice overwritten once, on first
post-rebase login — after that it's fully theirs again.

### 4. fastfetch terminal logo

`/etc/ublue-os/fastfetch.json` points `logo-directory` at
`/etc/spinofin/fastfetch/` (single file: `spinofin-ascii.txt`) instead of
Bluefin's rotating dino set.

This asset is deliberately placed under `/etc`, not `/usr/share`, unlike
every other slot in this document. `/etc` is 3-way merged on `bootc switch`
(see "`bootc switch` constraints" below), so `system_files/etc/...` here only
*seeds* the file on first deploy/rebase -- once it exists, a user is free to
edit `/etc/spinofin/fastfetch/spinofin-ascii.txt` directly (or drop
additional `*.txt`/image files alongside it; `shuffle-logo: true` picks
randomly among whatever's in the directory), and ostree will not clobber
those local changes on a later image update. Restoring the shipped default
is as easy as overwriting the file with this repo's version.

### 5. About / "System Details" logo

Fedora compiles `gnome-control-center` with a hardcoded distributor logo, so
the About panel ignores os-release `LOGO=` and instead loads two fixed files:
`/usr/share/pixmaps/fedora_logo_med.png` (light mode) and
`fedora_whitelogo_med.png` (dark mode) — ublue already replaces both with the
Bluefin logo, which is why `LOGO=` alone does nothing here. We override both
(250×102, matching Bluefin's slot) with spinofin wordmarks derived from
`spinofin-wordmark.svg`. We still set os-release `LOGO=spinofin-logo` (+ ship
`apps/spinofin-logo.svg`) because it's the correct spec-defined field other
tools read — just not what GNOME About uses.

## Deferred — Anaconda installer (`deferred/anaconda/`)

**Do not wire yet.** bootc-image-builder assembles the Anaconda installer
runtime separately from RPMs and embeds the spinofin image as the install
*payload* — files placed at `/usr/share/anaconda/…` in the image may not
propagate into the installer UI. Confidence: low, unconfirmed on a real BIB run.

Reliably controllable instead: the installer product name, via os-release
`PRETTY_NAME` (already wired — see below). Stage art here for later:
`sidebar-logo.png`, `sidebar-bg.png`, `topbar-bg.png` (transparent PNGs,
matched to the files they replace) — verify on a built installer once the
mechanism is confirmed.

## How it's built

- `build/15-branding.sh` (after `10-build.sh`) — merge-copies `system_files/`
  into `/` (which includes the panel-logo autostart entry and its script —
  no separate step needed), runs `dconf update` (compiles the `distro` +
  `gdm` dbs), refreshes the hicolor icon cache.
- `build/16-initramfs.sh` — regenerates the initramfs so the Plymouth splash
  embeds the spinofin watermark (early boot reads the initramfs, not `/usr`).
- Identity (`PRETTY_NAME`, `LOGO`) comes from the `IMAGE_PRETTY_NAME` /
  `IMAGE_LOGO` Containerfile ARGs, applied by `00-image-info.sh`.

## `bootc switch` constraints

The primary delivery path is rebasing an existing Bluefin install, which
shapes how this has to work:

- **`/usr` is fully replaced** → os-release, icons, Plymouth watermark, and the
  regenerated initramfs all apply cleanly.
- **`/etc` is 3-way merged** → our new dconf keyfiles are added (why GDM
  works) and `dconf-update.service` recompiles the dbs on boot. The fastfetch
  ASCII logo (`/etc/spinofin/fastfetch/spinofin-ascii.txt`) lives here too,
  specifically *because* of this merge behavior: it seeds on first deploy but
  a user's later edits to it survive subsequent `bootc upgrade`s, unlike
  everything in the `/usr` bullet above.
- **`/home` and the per-user dconf db are untouched** → the panel logo's XDG
  autostart migration (see above) exists specifically to reach in there once,
  since `distro.d` alone can't. Autostart entries run on every graphical
  login regardless of whether the account is new or rebased-in, unlike
  `ConditionFirstBoot=` systemd units, which don't fire on an existing
  install.

## Verify on a booted image

- **About name:** `grep -E '^PRETTY_NAME=' /etc/os-release` → `spinofin`. If still Bluefin, the os-release rewrite didn't run.
- **About logo:** comes from the compiled-in pixmaps, not os-release `LOGO`. Confirm `fedora_logo_med.png`/`fedora_whitelogo_med.png` are the spinofin wordmarks.
- **Panel logo:** check `cat /etc/dconf/db/distro.d/99-spinofin-branding` and which extension is live.
- **Panel logo migration:** confirm `~/.local/state/spinofin/branding-migrated` exists after first login, and `dconf read /org/gnome/shell/extensions/Logo-menu/custom-icon-path` returns our SVG path from the *user* db. To re-test, delete the stamp file and log out/in (or run `/usr/libexec/spinofin/branding-migrate-user-logo` directly).
- **Plymouth:** if the boot splash still shows Bluefin, the initramfs wasn't regenerated — confirm `16-initramfs.sh` ran.
- **fastfetch** renders monochrome (the `ublue-fastfetch` wrapper doesn't pass `--logo-color-N`).
