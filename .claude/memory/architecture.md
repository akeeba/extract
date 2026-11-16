# Architecture

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

## Engine bootstrap contract

`src/Bootstrap.php` must be required **exactly once** and loads every engine file in a strict
dependency order that is documented inline — reordering the `require_once` calls breaks class
resolution. It also defines `KICKSTART` (which suppresses Kickstart's Joomla/WordPress-specific
skip-file list) and `KSROOTDIR`. The engine's web-controller files (`mastersetup.php`,
`application.php`) are deliberately **not** vendored, which is why the `$_REQUEST`-touching helpers
in `preamble.php` are never reached.

## Extraction protocol

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

## PHP ↔ JS boundary

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
