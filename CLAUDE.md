# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
composer install                    # dependencies (Boson runtime + compiler)
php index.php                       # run the app in development (opens the window directly)
php bin/extract-cli.php [-s] <archive> <destination> [password]   # headless extraction harness
composer build                      # compile + package every platform into build/dist/
php build/tasks/compile-target.php --all   # compile all targets only, no packaging
build/fetch-sfx.sh [--force]        # download the patched signable SFX runtimes into build/sfx/
```

Phing targets (`build.xml`) mirror the same pipeline: `phing git` (compile only), `phing package`,
`phing run` (compile for this host and launch), `phing release` (package + GitHub release + CDN
upload; needs `build/build.properties`). See README.md for the full packaging matrix, signing
setup, and platform caveats.

### Testing

There is **no automated test suite** — no PHPUnit, no linter, no static-analysis config. Verify
changes by running `php bin/extract-cli.php` against real archives (it exercises the same
`ExtractorService` the GUI uses, minus Boson) and by launching the app with `php index.php`.
Windows and Linux binaries cross-compile on macOS but can only be run-tested on their own OS.

### Version bumps

The version lives in exactly one place: the topmost `CHANGELOG` entry. `build/tasks/set-version.php`
stamps it into `src/App.php`'s `VERSION` constant on every build, and the packaging scripts read it
back from there. Bump the version by adding a `CHANGELOG` entry — never by editing `src/App.php`.

## Architecture

Four layers, deliberately decoupled:

**`engine/`** — a vendored copy of the [Akeeba Kickstart](https://github.com/akeeba/kickstart)
unarchiver (`AKFactory`, `AKAbstractUnarchiver`, the JPA/JPS/ZIP unarchivers, AES, `AKText`).
It is **patched locally**, not a pristine upstream copy: `kickstart.setup.dryrun`,
`kickstart.setup.ignoreerrors`, `kickstart.setup.extract_list`, and the `type` field on the
`startfile` observer message are additions made here. Re-syncing from upstream means re-applying
those patches, not overwriting the directory.

**`src/`** — the GUI-free service layer (`Akeeba\Extract\`, PSR-4). Contains no Boson references at
all, which is what lets the CLI harness and the desktop app share it.

**`index.php`** — Boson wiring: creates the window, serves `public/` over a custom `app://` scheme,
registers the JS↔PHP bindings, and runs the blocking event loop.

**`public/`** — the WebView UI (`index.html` / `app.css` / `app.js`). Vanilla ES5-style IIFE, no
framework, no bundler, no npm — the files are served verbatim. Keep it that way.

### Engine bootstrap contract

`src/Bootstrap.php` must be required **exactly once** and loads every engine file in a strict
dependency order that is documented inline — reordering the `require_once` calls breaks class
resolution. It also defines `KICKSTART` (which suppresses Kickstart's Joomla/WordPress-specific
skip-file list) and `KSROOTDIR`. The engine's web-controller files (`mastersetup.php`,
`application.php`) are deliberately **not** vendored, which is why the `$_REQUEST`-touching helpers
in `preamble.php` are never reached.

### Extraction protocol

`ExtractorService` wraps the engine in a `begin()` / `step()` / `cancel()` API:

- The engine is **stateful and single-threaded**. `begin()` calls `AKFactory::nuke()` first; never
  start a second run without finishing or cancelling the first.
- `step()` performs one time-bounded engine tick (~1 s, via `kickstart.tuning.max_exec_time`) and
  must reset the timer each time. Callers loop until `done` is true.
- Warnings are read with `$engine->getWarnings()`, **not** from `getStatusArray()['Warnings']` — the
  status array returns only the delta since the previous tick, so earlier warnings would be lost.
- Faithful extraction is enforced by passing empty `rename_files`, `skip_files`, and
  `ignoredirectories` overrides to `AKFactory::getUnarchiver()`; Kickstart's defaults rewrite
  Joomla-specific files and must stay overridden.
- `percent` is derived from compressed bytes consumed ÷ total on-disk size of all archive parts, and
  is guaranteed monotonic non-decreasing.
- A **dry run** (`$dryRun = true`) walks the whole archive writing nothing, with `targetpath` left
  empty so `ProgressObserver::$fileList` collects archive-relative paths. This backs the "Pick a
  file or directory" tree; `ignoreErrors` is forced off for scans.

`ProgressObserver::__toString()` returns the FQCN because the engine keys attached observers by
their string form — it must stay stable and unique.

### PHP ↔ JS boundary

Bindings are registered in `index.php` with dot names (`extractor.begin`, `i18n.setLanguage`, …)
that Boson expands into nested `window` objects. Every binding body wraps its work in `try`/`catch`
and returns a **structured result** (`['ok' => bool, 'error' => string]` or a progress array) —
exceptions must never cross into the JS Promise. `app.js` drives extraction by polling
`extractor.step()` through `setTimeout`, yielding to the browser between ticks so the UI stays live.

Two platform-specific mechanisms worth knowing before touching `index.php`:

- **Drag-and-drop** has no native Boson event. It is implemented by intercepting the WebView's
  `file://` navigation attempt, cancelling it, and injecting the path via
  `window.__akeebaApplyArchive`. This cannot work on macOS (WKWebView hands over contents, not paths).
- **Launch-with-argument** (file associations) scans `$_SERVER['argv']` for the first readable
  `.jpa`/`.jps`/`.zip` and exposes it through the `initialArchive()` binding.

### Interface language

`en-GB` is the source of truth. `I18n\LanguageService` resolves the tag (stored override → OS locale
→ `en-GB`), loads `language/en-GB/en-GB.ini` as the fallback base, then the chosen language on top —
so a translation may omit keys it doesn't provide. The same catalogue serves both sides: it goes
into the engine's `AKText` table (so engine errors and warnings are translated) and is injected as
`window.__akeebaLang` via `scripts->preload`, which runs **before** `app.js` so the UI never flashes
untranslated keys. `app.js` applies it through `data-i18n`, `data-i18n-placeholder`, and
`data-i18n-tip` attributes.

Adding a language requires **no code change**: drop `language/<tag>/<tag>.ini` in place with an
`EXTRACT_LANGUAGE_ENDONYM` key naming the language in its own tongue. Language discovery uses
`scandir()`, never `glob()` — `glob()` does not support stream wrappers, so a compiled/PHAR build
would find only `en-GB`.

When you add or change an `en-GB` string, keep the other catalogues in step. Translation rules
(untranslatable technical tokens, `sprintf` placeholder preservation, the literal `\n` in
`EXTRACT_PH_EXTRACTLIST`, the ASCII-semicolon restriction in values) live in `build/glossaries/`.

### Compiled-build asset visibility

`boson.json` decides what exists inside a compiled binary. Runtime asset directories must be listed
under `mount` (currently `public` and `language`) and PHP sources under `build.finder` — a new
directory read at runtime will work under `php index.php` and silently be missing from every
compiled build until it is added there.

### Signing

A stock `boson compile` binary cannot be code-signed: the PHP payload is appended after the
Mach-O/PE signature region. macOS works around this with a patched phpmicro SFX (fetched into the
gitignored `build/sfx/` by `build/fetch-sfx.sh`) that loads its payload from a sibling file, letting
packaging split the output into a signable stub. Signing credentials live in the gitignored
`build/build.properties`; without them builds fall back to ad-hoc/unsigned. Details are in
`build/readme/01-macos-signing.md` through `04-exe-signing-on-macos.md`.

## Conventions

- PHP 8.4, `boson-php/*` pinned to `^0.19` (pre-1.0 — the API breaks between minor versions).
- Indentation is **not uniform**: `engine/`, `ExtractorService.php`, and `ProgressObserver.php` use
  tabs with Allman braces; the newer `src/` files use 4 spaces. Match the file you are editing.
- Commit subjects are short and imperative, often area-prefixed (`Windows: …`, `Build: …`, `Inno: …`),
  with a body explaining *why* when the change is non-obvious, and a `Signed-off-by` trailer.
- `.plans/` is gitignored internal scratch, not part of the deliverable.
