# Build and packaging

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

## Compiled-build asset visibility

`boson.json` decides what exists inside a compiled binary. Runtime asset directories must be listed
under `mount` (currently `public` and `language`) and PHP sources under `build.finder` — a new
directory read at runtime will work under `php index.php` and silently be missing from every
compiled build until it is added there.

## Signing

A stock `boson compile` binary cannot be code-signed: the PHP payload is appended after the
Mach-O/PE signature region. macOS works around this with a patched phpmicro SFX (fetched into the
gitignored `build/sfx/` by `build/fetch-sfx.sh`) that loads its payload from a sibling file, letting
packaging split the output into a signable stub. Signing credentials live in the gitignored
`build/build.properties`; without them builds fall back to ad-hoc/unsigned. Details are in
`build/readme/01-macos-signing.md` through `04-exe-signing-on-macos.md`.
