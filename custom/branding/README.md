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

### 3. Panel logo — Custom Command List

- File: `system_files/usr/share/icons/hicolor/scalable/actions/spinofin-logo-symbolic.svg` (optional colored variant: `.../spinofin-logo.svg`).
- Format: square viewBox, single path, `fill="currentColor"` (let GNOME recolor light/dark — don't hardcode). Renders at ~16–25px on the top bar, so the silhouette needs to read at that size.
- Mechanism: `menuicon-setting` flipped from `'ublue-logo-symbolic'` to `'spinofin-logo-symbolic'` in the distro dconf db. This is the extension actually enabled by default in Bluefin — the separate "Logo Menu" extension (`logomenu@aryan_k`) ships but is disabled, and only matters if we ever enable it (it can reuse the same SVG via `custom-icon-path`; it also already bundles a `kali-linux-logo-symbolic.svg` at icon index 9, if the Kali dragon is ever wanted there instead).

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
  into `/`, runs `dconf update` (compiles the `distro` + `gdm` dbs), refreshes
  the hicolor icon cache.
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
- **`/home` and the per-user dconf db are untouched** → a plain system default
  can't override a value the prior Bluefin setup already wrote into the
  user's dconf. That's why the panel logo needs a **lock**, not just a
  default — it forces the system value over the user db (tradeoff: users
  can't change the panel logo themselves; drop `locks/99-spinofin-branding`
  to allow it).
- First-boot services / user-setup hooks don't re-run on an existing install,
  so nothing here relies on them.

## Verify on a booted image

- **About name:** `grep -E '^PRETTY_NAME=' /etc/os-release` → `spinofin`. If still Bluefin, the os-release rewrite didn't run.
- **About logo:** comes from the compiled-in pixmaps, not os-release `LOGO`. Confirm `fedora_logo_med.png`/`fedora_whitelogo_med.png` are the spinofin wordmarks.
- **Panel logo:** check `cat /etc/dconf/db/distro.d/99-spinofin-branding` and which extension is live.
- **Plymouth:** if the boot splash still shows Bluefin, the initramfs wasn't regenerated — confirm `16-initramfs.sh` ran.
- **fastfetch** renders monochrome (the `ublue-fastfetch` wrapper doesn't pass `--logo-color-N`).
