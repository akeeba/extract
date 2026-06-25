# Akeeba Extract

A simple, cross-platform desktop application that extracts **Akeeba Backup** archives —
**JPA**, encrypted **JPS**, and standard **ZIP** — on macOS, Windows, and Linux.

The interface is deliberately minimal: pick the archive, choose an output folder (defaults to
the archive's own folder), enter a password if the archive is an encrypted JPS, press **Start**,
and watch the progress bar. When extraction completes you can open the output folder directly
from the app.

The extraction engine is the battle-tested unarchiver from
[Akeeba Kickstart](https://github.com/akeeba/kickstart), reused here behind a native desktop
GUI built with [Boson](https://bosonphp.com) (a PHP runtime paired with the operating
system's native WebView).

## Features

- Extracts JPA, JPS (AES-encrypted, password-protected), and ZIP archives.
- Handles multi-part archives automatically (`.jpa` + `.j01`, `.j02`, …).
- Native file/folder pickers and a live progress bar.
- **Open Output Folder** button on completion for quick access to extracted files.
- Clean error messages for common failure cases: corrupt archive, wrong password,
  unwritable destination, missing multi-part file, user cancel.
- Engine warnings surfaced non-intrusively in a collapsible area.
- Single self-contained binary per platform — no PHP installation required by end users.

## Usage

1. Launch **Akeeba Extract**.
2. Click **Browse…** next to *Archive file* and choose your `.jpa`, `.jps`, or `.zip` file.
3. The *Output folder* defaults to the archive's directory; click **Browse…** to change it.
4. For an encrypted **JPS** archive, type the password in the *Password* field that appears.
5. Click **Start**. All inputs are locked during extraction; click **Cancel** to abort.
6. On success, click **Open Output Folder** to open the destination in your file manager.

## Building from source

Requirements (development machine):

- PHP **8.4+** with the `ffi`, `openssl`, and `zlib` extensions (`bz2` recommended).
- [Composer](https://getcomposer.org).
- Boson compiler (`boson-php/compiler`, installed via Composer). macOS 14+ for development.

```bash
# Install dependencies (including Boson runtime and compiler)
composer install

# Run in development mode (opens the app window directly)
php index.php

# Compile self-contained binaries for all target platforms (from macOS)
# Downloads runtime stubs on first run (~150 MB total); requires network.
php vendor/bin/boson compile

# Package the macOS arm64 app bundle (after compile)
./build/macos-app.sh arm64        # produces Akeeba Extract.app in build/output/macos/aarch64/
./build/make-dmg.sh  arm64        # produces Akeeba-Extract-arm64.dmg in build/output/

# macOS x86_64 (Intel) variant
./build/macos-app.sh amd64
./build/make-dmg.sh  amd64
```

### Compile output

| Target | Directory | Files |
|--------|-----------|-------|
| macOS arm64 | `build/output/macos/aarch64/` | `akeeba-extract`, `libboson-darwin-universal.dylib`, `public/` |
| macOS amd64 | `build/output/macos/amd64/` | same |
| Windows amd64 | `build/output/windows/amd64/` | `akeeba-extract.exe`, `libboson-windows-x86_64.dll`, `public/` |
| Linux amd64 | `build/output/linux/amd64/` | `akeeba-extract`, `libboson-linux-x86_64.so`, `public/` |
| PHAR (any OS with PHP) | `build/output/phar/` | `akeeba-extract.phar`, all runtime dylibs, `public/` |

### Windows installer

The Inno Setup script `build/windows-installer.iss` creates a proper Windows installer.
Build it on a Windows machine with [Inno Setup 6](https://jrsoftware.org/isinfo.php):

```bat
php vendor/bin/boson compile
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" build\windows-installer.iss
```

Output: `build/output/Akeeba-Extract-Setup.exe`.

### Known limitations

- **No code signing or notarization.** macOS users will see a Gatekeeper warning on first
  launch; right-click → Open to bypass it. Windows users may see a SmartScreen prompt.
- **Windows and Linux binaries are compiled on macOS** via Boson's cross-compilation support
  but must be run-tested on their respective operating systems.
- **BZip2 (bz2) extension not bundled.** JPA archives that use BZip2 compression will fail to
  extract. The standard Boson SFX bundles do not include `bz2`. To add it, build a custom SFX
  by forking [boson-php/backend-src](https://github.com/boson-php/backend-src) and following
  the README's "custom extensions" workflow, then reference the custom SFX in `boson.json`.
- **Boson is pre-1.0** (currently 0.19.x); the API may change between minor versions. Pin
  `boson-php/compiler` and `boson-php/runtime` versions in `composer.json`.

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
