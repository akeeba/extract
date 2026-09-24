# Translations

Akeeba Extract is NOT a Joomla extension: there is no XML manifest to update when adding a language.
The catalogues are Joomla-style INI files at `language/<tag>/<tag>.ini`, with `en-GB` as the canonical
source. The shared translation rules are in `build/glossaries/README.md`; the architecture is in the
root `AGENTS.md` ("Interface language").

## Keep every catalogue at exact key parity

Any code change or new feature that adds, changes or removes a language string MUST be propagated to
all supported languages (every directory under `language/`) in the same round.

**Why:** The catalogues must stay at exact key parity with `en-GB`. A translation may technically omit
keys (it falls back to `en-GB`), but that leaves untranslated English in the UI and drifts the
catalogues apart.

**How to apply:** Translate with the `machine-translation` skill (`akeeba-project-management`
plugin), which drives full runs. Consult **and update** `build/glossaries/<tag>.md` on every
translation run. Afterwards verify with a script that diffs each catalogue's keys and `sprintf`
placeholder multisets against `en-GB`, and by loading each language through the app (see the runtime
wiring below).

## Runtime wiring worth knowing

Details beyond the `AGENTS.md` summary, for when you touch the i18n code:

- `engine/AKText.php` is a trimmed port of Kickstart's `text.php`: `AKText::_()`, `AKText::sprintf()`,
  `loadTranslationFile()`, `getStrings()`, `asJavascript()`. Engine errors and warnings go through it.
- `src/I18n/LanguageService.php` detects the OS locale from `LC_ALL` → `LC_MESSAGES` → `LANG` →
  `locale_get_default()` (ported from Grafida). `catalog()` returns
  `{tag, override, endonym, available, strings}`.
- The user's override is persisted by `src/Settings.php` as the `ui_language` key in
  `settings.json` under `Paths::configDir()`. The `i18n.setLanguage(tag)` binding sets it and returns
  the fresh catalogue.
- Front end: `public/app.js` has `t()` / `tf()` helpers and renders the language picker
  (`🌐 (Automatic)` plus `<flag> <endonym>`, the flag derived from the tag's country part). The CSS
  drop overlay reads a translated `data-drop-label`.
- Packaging: besides the Boson `mount`, the macOS and Windows packaging scripts copy `language/` next
  to the binary. `scandir()` / `FilesystemIterator` were verified end to end over a real filesystem,
  an embedded PHAR and `Phar::mount`.

**Why:** These are the pieces that must stay in step when the language mechanism changes.

**How to apply:** Read before changing language loading, the picker, settings persistence, or
packaging of `language/`.
