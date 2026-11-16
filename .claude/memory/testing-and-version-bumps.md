# Testing and version bumps

## Testing

There is **no automated test suite** — no PHPUnit, no linter, no static-analysis config. Verify
changes by running `php bin/extract-cli.php` against real archives (it exercises the same
`ExtractorService` the GUI uses, minus Boson) and by launching the app with `php index.php`.
Windows and Linux binaries cross-compile on macOS but can only be run-tested on their own OS.

## Version bumps

The version lives in exactly one place: the topmost `CHANGELOG` entry. `build/tasks/set-version.php`
stamps it into `src/App.php`'s `VERSION` constant on every build, and the packaging scripts read it
back from there. Bump the version by adding a `CHANGELOG` entry — never by editing `src/App.php`.
