# AGENTS.md

This file provides guidance to coding agents when working with code in this repository.

Akeeba Extract is a desktop app (PHP + Boson) that extracts JPA, JPS and ZIP backup archives. `engine/` is a locally patched vendored copy of the Kickstart unarchiver; `src/` is the GUI-free service layer; `index.php` is the Boson wiring; `public/` is the WebView UI.

## Commands

```bash
composer install                    # dependencies (Boson runtime + compiler)
php index.php                       # run the app in development (opens the window directly)
php bin/extract-cli.php [-s] <archive> <destination> [password]   # headless extraction harness
composer build                      # compile + package every platform into build/dist/
php build/tasks/compile-target.php --all   # compile all targets only, no packaging
build/fetch-sfx.sh [--force]        # download the patched signable SFX runtimes into build/sfx/
```

There is **no automated test suite**; verify with `php bin/extract-cli.php` against real archives.

## Always-on rules

- Bump the version by adding a `CHANGELOG` entry — never by editing `src/App.php`.
- `engine/` is **patched locally**, not pristine upstream: never overwrite it when re-syncing from Kickstart.
- `src/Bootstrap.php` must be required exactly once; do not reorder its `require_once` calls.
- `public/` is vanilla ES5-style JS with no framework, bundler or npm. Keep it that way.
- A new runtime asset directory must be added to `boson.json` (`mount` / `build.finder`) or it silently vanishes from compiled builds.
- Keep every `language/` catalogue in step with `en-GB`.
- Run every `git commit` and `git tag` outside the sandbox from the first attempt; never use `--no-gpg-sign`.

## Project memory

Project memory lives in `.claude/memory/`. Read the matching file before starting that kind of work.

| File | Read it when… |
|------|---------------|
| [`architecture.md`](.claude/memory/architecture.md) | Before you touch `src/`, `engine/`, `index.php` or `public/`, the engine bootstrap, the extraction protocol (`ExtractorService`), the PHP/JS bindings, or drag-and-drop |
| [`translations.md`](.claude/memory/translations.md) | Before you add, change, remove or translate a language string, or change how languages are loaded, picked or packaged |
| [`build-and-packaging.md`](.claude/memory/build-and-packaging.md) | Before you run Composer or Phing build targets, change `boson.json`, or deal with code signing and packaging |
| [`testing-and-version-bumps.md`](.claude/memory/testing-and-version-bumps.md) | Before you verify a change or bump the version |
| [`conventions.md`](.claude/memory/conventions.md) | Before you write PHP or JS here (indentation, PHP/Boson versions) or write a commit message |
| [`git-commit-signing.md`](.claude/memory/git-commit-signing.md) | Before you run `git commit` or `git tag` |
| [`recording-memories.md`](.claude/memory/recording-memories.md) | Before you add or change a project memory file |
