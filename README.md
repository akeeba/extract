# Akeeba Extract

Extracts **Akeeba Backup** archives on your desktop.

> [!IMPORTANT]
> This repository is still in a Technology Preview stage. Use at your own risk.

This application supports **JPA**, encrypted **JPS**, and standard **ZIP**. It is cross-platform; it runs on macOS, Windows, and Linux.

The interface is deliberately minimal: pick the archive, choose an output folder (defaults to the archive's own folder), enter a password if the archive is an encrypted JPS, press **Start**, and watch the progress bar. When extraction completes you can open the output folder directly from the app.

The extraction engine is the battle-tested unarchiver from[Akeeba Kickstart](https://github.com/akeeba/kickstart), reused here behind a native desktop GUI built with [Boson](https://bosonphp.com) (a PHP runtime paired with the operating system's native WebView).

## Features

* Extracts JPA, JPS (AES-encrypted, password-protected), and ZIP archives.
* Handles multi-part archives automatically (`.jpa` + `.j01`, `.j02`, …).
* **Selective extraction:** extract only the files you need by entering glob patterns, or use the built-in archive browser to pick files and folders from a tree and have the patterns filled in for you.
* **Skip most errors:** optionally keep going past files that cannot be written (e.g. a backup made on Linux containing names such as `foo?bar` that are invalid on Windows) or corrupt entries, instead of aborting the whole run. Each skipped entry is listed under Warnings.
* Native file/folder pickers and a live progress bar.
* **Open Output Folder** button on completion for quick access to extracted files.
* Clean error messages for common failure cases: corrupt archive, wrong password, unwritable destination, missing multi-part file, user cancel.
* Engine warnings surfaced non-intrusively in a collapsible area.
* Single self-contained binary per platform — no PHP installation required by end users.

## Usage

1. Launch **Akeeba Extract**. You can pick the archive in any of three ways:
   - Click **Browse…** next to *Archive file* and choose your `.jpa`, `.jps`, or `.zip` file.
   - **Drag and drop** an archive onto the window (does not work on macOS).
   - **Open the app with the archive as an argument** — e.g. via a Windows/Linux file association or `akeeba-extract /path/to/backup.jpa` from a terminal.
2. The *Output folder* defaults to the archive's directory; click **Browse…** to change it.
3. For an encrypted **JPS** archive, type the password in the *Password* field that appears.
4. *(Optional)* To extract only some of the archive, use the **Files to extract** box. Type one
   [glob pattern](https://en.wikipedia.org/wiki/Glob_(programming)) per line (e.g. `images/*` or
   `config/settings.php`), or click **Pick a file or directory…** to browse the archive contents in a
   tree, tick the files/folders you want, and press **Insert**. Picking a folder inserts a `folder/*`
   pattern; picking a file inserts its path verbatim. Leave the box empty to extract everything.
5. *(Optional)* Tick **Skip most errors** to keep extracting when an individual file cannot be written
   (for example a Linux-only name such as `foo?bar` on Windows) or an entry is corrupt, instead of
   aborting. Skipped entries are reported in the collapsible **Warnings** area when the run finishes.
6. Click **Start**. All inputs are locked during extraction; click **Cancel** to abort.
7. On success, click **Open Output Folder** to open the destination in your file manager.

> [!TIP]
> Always select the **main** archive file (`.jpa` / `.jps` / `.zip`). Multi-part pieces
> (`.j01`, `.j02`, … / `.z01`, …) are discovered and read automatically.


### Open file behaviour per platform

- **Browse… (file picker):** works on macOS, Windows, and Linux. On macOS you will be able to select files which are not backup archives due to an OS limitation.
- **Drag-and-drop:** works on Windows and Linux. **Not available on macOS** — its system WebView (WKWebView) hands the page only the dropped file's contents, never its path, so the app can't locate the archive. The window shows a clear message pointing you to Browse… if you drop a file there.
- **Launch with a file argument** (file association or `akeeba-extract /path/to/archive.jpa`): works on Windows and Linux, and from a macOS terminal. macOS *Finder* file associations aren't wired up (they use Apple Events rather than argv).

### Selective extraction

By default the entire archive is extracted. To extract only part of it, list one or
more **glob patterns** in the *Files to extract* box — one per line (commas also work).
Leave the box empty to extract everything.

Patterns are matched against each entry's **archive-relative path** (e.g.
`config/settings.php`), and matching is **case-sensitive**:

| Pattern | Matches |
| --- | --- |
| `config/settings.php` | exactly that one file |
| `images/*` | everything under `images/`, **at any depth** (e.g. `images/a.png` *and* `images/icons/b.png`) |
| `*.sql` | every entry whose path ends in `.sql`, in any folder |
| `config/db.php, config/settings.php` | either file (comma- or newline-separated) |

> [!NOTE]
> Unlike a shell, `*` here also matches the `/` separator, so a single `folder/*`
> pattern covers the whole sub-tree beneath `folder/`. `?` matches any single character.

**Pick a file or directory…** opens a browser of the archive's contents as a checkable
tree. Tick any files and folders and press **Insert** to append the matching patterns to
the box: a folder becomes `folder/*`, a file becomes its path verbatim. Ticking a folder
selects everything inside it.

The first time you open the picker, the app performs a quick **dry run** over the whole
archive — it reads (and, for JPS, decrypts with the password you entered) every part to
enumerate the entries, **without writing anything to disk**. Progress is shown on the main
window's bar and can be cancelled. The resulting list is cached, so reopening the picker is
instant; it is rescanned automatically if you change the archive or the password.

### Skip most errors

By default, the extraction stops at the first problem it cannot recover from — typically a
file that cannot be written to disk, or a corrupt entry in the archive. Tick **Skip most
errors** before pressing **Start** to make the engine *continue* past such problems instead:

- A file that cannot be written (for example a name like `foo?bar#baz` that is perfectly
  valid on Linux but illegal on Windows, or a target the operating system refuses) is left
  out and extraction moves on to the next entry. This applies to JPA, JPS, and ZIP archives.
- For **JPA** and **JPS** archives, a corrupt entry header is skipped by scanning ahead for
  the next valid one, so a localised bit of corruption no longer dooms the whole archive.

Every skipped entry is recorded as a warning, surfaced in the collapsible **Warnings** area
once the run finishes, so you always know exactly what was left out. This mirrors the
long-standing *Skip most errors* option of [Akeeba Kickstart](https://github.com/akeeba/kickstart).

> [!NOTE]
> This option only changes how *recoverable* errors are handled. Fatal conditions — a wrong
> JPS password, a completely unreadable archive, or a missing multi-part file — still stop
> the run with a clear error message.

The headless CLI harness (`bin/extract-cli.php`) exposes the same behaviour through a
`-s` / `--skip-errors` flag.

## Building from source

Requirements (development machine):

- PHP **8.4+** with the `ffi`, `openssl`, and `zlib` extensions (`bz2` is optional as we never allowed creating backup archives using this compression method).
- [Composer](https://getcomposer.org).
- Boson compiler (`boson-php/compiler`, installed via Composer). macOS 14+ for development.
- *(Optional)* [Phing](https://www.phing.info) on your `PATH` (`composer global require phing/phing`) if you want the Phing-driven workflow below instead of the plain `composer build` / `./build/*.sh` scripts. Not required for a basic build.

```bash
# Install dependencies (including Boson runtime and compiler)
composer install

# Run in development mode (opens the app window directly)
php index.php
```

The application version is a single source of truth: the topmost entry of the root
`CHANGELOG` file (e.g. `Akeeba Extract 0.1`). Every build stamps that version into
`src/App.php`'s `VERSION` constant (`php build/tasks/set-version.php`), and every
packaging script reads it back from there — bump the version by adding a new
`CHANGELOG` entry, not by editing `src/App.php` directly.

### One-command build & package (all platforms)

```bash
composer build
```

This runs `build/build-all.sh`, which compiles every target and packages each
platform's distributable into `build/dist/` (the version comes from the topmost
`CHANGELOG` entry, stamped into `src/App.php`):

| Platform | Artifact |
| --- | --- |
| macOS arm64 | `Akeeba-Extract-<version>-macos-arm64.dmg` (`.app` bundle inside) |
| macOS x86_64 | `Akeeba-Extract-<version>-macos-amd64.dmg` |
| Linux x86_64 | `Akeeba-Extract-<version>-linux-amd64.tar.gz` |
| Windows x86_64 | `Akeeba-Extract-<version>-windows-amd64-Setup.exe` (installer) — see the Windows note below |
| Any | `Akeeba-Extract-<version>.phar` |

Notes:

* The same pipeline also runs **automatically after `composer update`** (wired via the `post-update-cmd` Composer hook).
* The first compile downloads the Boson runtime stubs (~150 MB total) and needs network access; subsequent runs use the cache.
* `.app`/`.dmg` packaging only happens on a macOS host (it uses `hdiutil`).
* **Windows installer:** the pipeline builds the NSIS installer from `build/windows-installer.nsi` using **NSIS**, whose `makensis` compiler runs natively on macOS and Linux — so the installer cross-compiles from your dev machine with no Wine/Docker/Windows host. Install it once with `brew install makensis` (macOS) or your distro's `nsis` package (Linux). If `makensis` is absent, the pipeline falls back to Inno Setup's `iscc` (if present, e.g. on Windows, using `build/windows-installer.iss`), and failing that, a portable `Akeeba-Extract-<version>-windows-amd64.zip`.
* If dev dependencies are absent (e.g. `composer update --no-dev`), the build step detects the missing compiler and skips cleanly without failing.

The individual packaging scripts can also be run by hand:

```bash
php vendor/bin/boson compile          # compile all targets only
./build/macos-app.sh arm64            # → Akeeba Extract.app in build/output/macos/aarch64/
./build/make-dmg.sh  arm64            # → Akeeba-Extract-<version>-macos-arm64.dmg in build/dist/
./build/macos-app.sh amd64            # macOS x86_64 (Intel) variant
./build/make-dmg.sh  amd64
./build/make-windows-installer.sh     # → installer or portable .zip in build/dist/
./build/make-linux-tarball.sh amd64   # → .tar.gz in build/dist/
./build/make-phar-dist.sh             # → .phar in build/dist/
```

### Phing workflow

The same build is also available through [Phing](https://www.phing.info) targets
(`build.xml`), for muscle-memory parity with Akeeba's other Boson-based apps:

```bash
phing git             # compile binaries for every platform (no packaging)
phing package          # compile + package every platform into build/dist/
phing run              # compile the binary for THIS host and launch it
phing release           # package everything, publish a GitHub release, push the update JSON to the CDN
```

`phing git`/`phing package` mirror `composer build:git`/`composer build:package`
(added as thin wrappers). `phing release` needs `build/build.properties` — copy
`build/build.sample.properties` and fill in a GitHub token and CDN FTPS
credentials; it fails fast with a clear message if they're missing. macOS
packaging is ad-hoc signed only (see "Releases are unsigned" above), same as
the plain `build-all.sh` path — Phing doesn't add signing capability Boson
doesn't otherwise support.

### Compile output

| Target | Directory | Files |
|--------|-----------|-------|
| macOS arm64 | `build/output/macos/aarch64/` | `akeeba-extract`, `libboson-darwin-universal.dylib`, `public/` |
| macOS amd64 | `build/output/macos/amd64/` | same |
| Windows amd64 | `build/output/windows/amd64/` | `akeeba-extract.exe`, `libboson-windows-x86_64.dll`, `public/` |
| Linux amd64 | `build/output/linux/amd64/` | `akeeba-extract`, `libboson-linux-x86_64.so`, `public/` |
| PHAR (any OS with PHP) | `build/output/phar/` | `akeeba-extract.phar`, all runtime dylibs, `public/` |

### Windows installer

The build pipeline produces a proper Windows installer,
`build/dist/Akeeba-Extract-<version>-windows-amd64-Setup.exe`.

**Preferred — NSIS (cross-compiles from any OS).** The NSIS `makensis` compiler runs
natively on macOS and Linux, so the installer is built from `build/windows-installer.nsi`
without a Windows host. Install it once (`brew install makensis` on macOS, your distro's
`nsis` package on Linux) and `build/build-all.sh` (or `build/make-windows-installer.sh`)
picks it up automatically. To run it by hand (both `-D` values are required — there is no
hardcoded default):

```bash
php vendor/bin/boson compile
makensis -V2 -DAPPVERSION=0.1 build/windows-installer.nsi
```

**Fallback — Inno Setup (Windows only).** If `makensis` is unavailable but Inno Setup's
`iscc` is present, the pipeline falls back to `build/windows-installer.iss`. Build it on a
Windows machine with [Inno Setup 6](https://jrsoftware.org/isinfo.php):

```bat
php vendor/bin/boson compile
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" /DAppVersion=0.1 build\windows-installer.iss
```

If neither compiler is found, the pipeline produces a portable
`Akeeba-Extract-<version>-windows-amd64.zip` instead.

### Known limitations

* **No code signing or notarization — and this is currently *impossible*, not a decision we've deferred.** `boson compile` produces a phpmicro self-executable whose PHP payload is appended *after* the binary's code-signature region. Apple's `codesign` (and, we expect, Windows `signtool`) requires the signature to be the trailing content of the file, so the appended payload makes signing fail; the payload can't be relocated without breaking startup, since phpmicro locates it as "Mach-O image-end to EOF". We verified this in depth for macOS and, because Boson uses the same binary format on every platform, did not attempt Windows signing. Linux is unaffected (no OS-enforced binary-signature gate). We'll wire up Developer ID signing/notarisation as soon as Boson can emit a signable binary. Until then: macOS users will see a Gatekeeper warning on first launch (right-click → Open to bypass it); Windows users may see a SmartScreen prompt (More info → Run anyway).
* **Windows and Linux binaries are compiled on macOS** via Boson's cross-compilation support but must be run-tested on their respective operating systems.
* **BZip2 (bz2) extension not bundled.** JPA archives that use BZip2 compression will fail to extract. The standard Boson SFX bundles do not include `bz2`. To add it, build a custom SFX by forking [boson-php/backend-src](https://github.com/boson-php/backend-src) and following the README's "custom extensions" workflow, then reference the custom SFX in `boson.json`.
* **Boson is pre-1.0** (currently 0.19.x); the API may change between minor versions. Pin `boson-php/compiler` and `boson-php/runtime` versions in `composer.json`.
* **The file picker scans the whole archive on first open.** Enumerating the entries reads (and, for JPS, decrypts) every part, so for a large multi-gigabyte archive the first open of *Pick a file or directory…* can take a while. It runs with a cancellable progress bar and the result is cached for the session.

Cross-platform binaries (Windows `.exe`, Linux ELF) are compiled on macOS via Boson's
cross-compilation support but must be run-tested on their respective operating systems.

## License

Akeeba Extract is free software.

> Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
>
> This program is free software: you can redistribute it and/or modify it under the terms of
> the GNU General Public License as published by the Free Software Foundation, either version 3
> of the License, or (at your option) any later version.
>
> This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
> without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See
> the GNU General Public License for more details.
>
> You should have received a copy of the GNU General Public License along with this program. If
> not, see <https://www.gnu.org/licenses/>.

The full license text is in [`LICENSE.txt`](LICENSE.txt).

The reused extraction engine in `engine/` is also licensed under the GNU GPL v3 or later,
Copyright (c) 2008–2026 Nicholas K. Dionysopoulos / Akeeba Ltd.
