# spinofin branding assets

Drop-in slots for spinofin's OS-identity branding (boot splash, login, panel
logo, installer). Replace the Bluefin/ublue logos that the base image ships.

This is **OS-identity** branding only — it is *not* a desktop reskin. Wallpapers
(including the Bluefin dinosaurs), the GTK/icon theme, and accent colors stay
Bluefin by project decision. See the repo README's aesthetic note.

## No-layering posture

Nothing here installs a package. Every surface is either:

- a **file overwrite** of an asset the base image already ships, or
- a **dconf / gschema default** that points at an asset we ship.

So the `no-layering-check.yml` guard (which only greps for
`dnf5|yum|apt|rpm-ostree install`) does not fire, and there is nothing to unwind
at the eventual Track-B (GNOME OS bootc) migration.

## Layout

```
custom/branding/
├── system_files/        # WIRED surfaces — copied verbatim into / by the build step.
│                        #   Mirrors on-image paths 1:1 (ublue system_files idiom).
│   └── usr/share/...
├── deferred/            # NOT wired. Mechanism unconfirmed — do not assume it works.
│   └── anaconda/
└── optional/            # NOT wired. Aesthetic surfaces we are choosing to keep
    ├── fastfetch/       #   Bluefin on for now. Only fill if we decide to diverge.
    └── about/
```

`system_files/` is the only tree the build step touches. `deferred/` and
`optional/` are staging areas only, so an art drop never silently changes the
image before the mechanism is validated.

## Source-of-truth assets (recommended)

Author two masters in Claude Design, then derive every raster/variant from them:

1. **Wordmark** (horizontal lockup) → splash, login, installer, About.
2. **Symbolic glyph** (square, single-color) → panel icon, About icon.

---

## WIRED slots (`system_files/`)

### 1. Boot splash — Plymouth   ·   status: ready for art, build step pending

| | |
|---|---|
| Drop file(s) here | `system_files/usr/share/plymouth/themes/spinner/watermark.png`<br>`system_files/usr/share/plymouth/themes/spinner/silverblue-watermark.png` |
| Overwrites in image | same paths under `/usr/share/plymouth/themes/spinner/` |
| Filenames | **must stay** `watermark.png` and `silverblue-watermark.png` (overwrite) |
| Format | PNG-32, transparent background, **light/white** artwork (boot bg is dark) |
| Stock size | 149 × 43 |
| Produce at | ~**300 × 88** (Plymouth does **not** scale; larger = crisper on HiDPI) |
| Notes | The `spinner` theme draws this watermark; the `bgrt` theme inherits spinner's image dir, so this one file covers both. Replace **both** PNGs; confirm the active theme on a booted image. |

### 2. Login screen — GDM logo   ·   status: ready for art, dconf activation pending

| | |
|---|---|
| Drop file here | `system_files/usr/share/pixmaps/spinofin-gdm-logo.png` |
| Filename | our choice (net-new file); the dconf key will point at it |
| Format | PNG-32 transparent, light monochrome, ~**150 × 61** (SVG also fine) |
| Mechanism | `org.gnome.login-screen logo` in a `gdm` dconf db |
| Status | Bluefin sets **no** greeter logo today, so this is an **addition**, not a replacement. The dconf keyfile + `dconf update` lands in the wiring unit. |

### 3. Panel logo — Custom Command List (the live one)   ·   status: ready for art, dconf flip pending

| | |
|---|---|
| Drop file here | `system_files/usr/share/icons/hicolor/scalable/actions/spinofin-logo-symbolic.svg` |
| Optional coloured | `…/actions/spinofin-logo.svg` |
| Format | **square** viewBox, single path, `fill="currentColor"` (let GNOME recolor for light/dark — do **not** hardcode color), no embedded raster |
| Renders at | ~16–25 px on the top bar → silhouette must read at that size (bold, simple) |
| Mechanism | flip `menuicon-setting` from `'ublue-logo-symbolic'` to `'spinofin-logo-symbolic'` (icon-theme **name**, not a path) in the distro dconf db |
| Why this one | This is the extension actually **enabled by default** in Bluefin. The literal "Logo Menu" extension (`logomenu@aryan_k`) is bundled but **disabled** — only touch it if we explicitly enable it (see note below). |

> Note on "Logo Menu": if we ever enable `logomenu@aryan_k`, the same
> `spinofin-logo-symbolic.svg` can drive it via
> `/org/gnome/shell/extensions/Logo-menu/use-custom-icon=true` +
> `custom-icon-path=/usr/share/icons/hicolor/scalable/actions/spinofin-logo-symbolic.svg`.
> (That extension also already bundles `kali-linux-logo-symbolic.svg` at icon
> index 9, if the Kali dragon is ever wanted there instead.)

---

## DEFERRED slot (`deferred/anaconda/`)   ·   status: do NOT wire yet

Installer dialogue branding. **Low confidence:** bootc-image-builder assembles
the Anaconda installer runtime separately (from RPMs) and embeds the spinofin
image as the install *payload*, so files placed in the image at
`/usr/share/anaconda/…` may **not** propagate into the installer the user sees.

Reliably controllable instead: the installer **product name**, via os-release
`PRETTY_NAME` — which is currently still **"My Custom OS"** (the
`build/00-image-info.sh` default; `IMAGE_PRETTY_NAME` is never set as an ARG).
Worth fixing regardless, since that string also shows in GNOME About and the
bootloader entry.

Stage art here for when the mechanism is confirmed on a real BIB run (expect it
may need a `product.img`-style overlay or an Anaconda profile drop-in):

| File | Format | Notes |
|---|---|---|
| `sidebar-logo.png` | transparent PNG | product logo (keep upstream name) |
| `sidebar-bg.png` | transparent PNG | fades into a defined `@product_bg_color` |
| `topbar-bg.png` | transparent PNG | same |

Match dimensions to the file being replaced; verify on a built installer.

---

## WIRED — fastfetch + About

### fastfetch terminal logo
`/etc/ublue-os/fastfetch.json` points `logo-directory` at
`/usr/share/spinofin/fastfetch/` (single file → deterministic) instead of
Bluefin's rotating dino set. This is the one surface that diverges from the
"keep the Bluefin aesthetic" note; delete that JSON to restore the dino shuffle.

### About / "System Details" logo
os-release `LOGO=spinofin-logo` (set via the `IMAGE_LOGO` ARG →
`00-image-info.sh`; last-assignment-wins overrides Fedora's `fedora-logo-icon`).
The named icon is the **colored** mark shipped at
`usr/share/icons/hicolor/scalable/apps/spinofin-logo.svg` — colored (not
symbolic) so it reads on both light and dark About backgrounds without needing
variants. gnome-control-center reads `LOGO` as a themed icon name.

---

## Wiring (now in place)

Build steps (Containerfile, after `10-build.sh`):
- `build/15-branding.sh` — merge-copies `system_files/` into `/`, runs
  `dconf update` (compiles the `distro` + `gdm` dbs), refreshes the hicolor
  icon cache.
- `build/16-initramfs.sh` — regenerates the initramfs so the Plymouth boot
  splash embeds the spinofin watermark (early boot reads the initramfs, not
  `/usr`). Mirrors the base's dracut invocation; no package install.

Identity (`PRETTY_NAME`, `LOGO`, ...) is the `IMAGE_PRETTY_NAME` / `IMAGE_LOGO`
ARGs consumed by `00-image-info.sh`, which now **replaces keys in place** rather
than gating on `VARIANT_ID` (the Bluefin base sets `VARIANT_ID`, so the old
guard skipped the whole block — that was why About/PRETTY_NAME stayed Bluefin).

Wired surfaces: Plymouth watermark (+ initramfs), GDM login logo, panel logo
(**both** Custom Command List `menuicon-setting` and Logo Menu `custom-icon-path`,
with dconf **locks**), fastfetch logo, About-page `LOGO=`. Still **deferred**:
Anaconda installer art.

## Distribution = `bootc switch` (what that constrains)

The primary delivery path is rebasing an existing Bluefin install with
`bootc switch`. That has specific semantics the wiring is built around:
- **`/usr` is fully replaced** → os-release, icons, Plymouth watermark, the
  regenerated initramfs, fastfetch logo all apply.
- **`/etc` is 3-way merged** → our new dconf keyfiles/profile are added (this is
  why GDM + fastfetch worked); `dconf-update.service` recompiles dbs on boot.
- **`/home` and the per-user dconf db are untouched** → a plain system default
  can't override a value the prior Bluefin setup wrote into the user's dconf.
  That is why the panel logo needs **locks**, not just a default: a lock forces
  the system value over the user db. (Tradeoff: users can't change the panel
  logo; drop `locks/99-spinofin-branding` to allow it.)
- First-boot services / user-setup hooks **do not re-run** on an existing
  install, so nothing here relies on them.

## Verify on a booted image (can't be checked at build time)

- **About / name:** `grep -E '^(PRETTY_NAME|LOGO)=' /etc/os-release` → expect
  `spinofin` / `spinofin-logo`. If still Bluefin, the os-release rewrite didn't
  run (rebuild and re-switch).
- **Panel logo:** if unchanged, check the keyfile arrived
  (`cat /etc/dconf/db/distro.d/99-spinofin-branding`) and which extension is
  live; the locks force both Custom Command List and Logo Menu.
- **Plymouth:** if the boot splash still shows Bluefin, the initramfs wasn't
  regenerated — confirm `16-initramfs.sh` ran in the build.
- **fastfetch** renders monochrome: the `ublue-fastfetch` wrapper doesn't pass
  `--logo-color-N`, so the `$1`/`$2` regions collapse to one accent color. Delete
  `etc/ublue-os/fastfetch.json` to restore Bluefin's dino shuffle.
