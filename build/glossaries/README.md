# Translation glossaries

One file per language, consulted and updated on every translation run to keep
terminology consistent across the Akeeba Extract UI catalogues
(`language/<tag>/<tag>.ini`, source of truth: `en-GB`).

## Rules for every language

- **Never translate** technical tokens: file extensions (`.jpa`, `.jps`, `.zip`,
  `.j01`, `.z01`), `JPS`, `Linux`, `Windows`, `WebView`, glob examples
  (`images/*`, `config/settings.php`).
- **Preserve every `sprintf` placeholder** verbatim and in order: `%s`, `%d`,
  and positional forms like `%1$s`, `%2$s`, `%4$s`. Sequences such as
  `.%s, .%s01, .%2$s02` must be copied character-for-character.
- Keep the literal `\n` (backslash-n) in `EXTRACT_PH_EXTRACTLIST`.
- Avoid ASCII semicolons (`;`) inside values; use the language's normal
  punctuation (comma, em dash, Greek `·`) — the INI parser has special-cased `;`.
- `EXTRACT_LANGUAGE_ENDONYM` is the language's own name in its own tongue.
- `EXTRACT_FILES_ONE` / `EXTRACT_FILES_MANY` are the singular / plural of the
  word "file" (the app selects between them by count). Some languages (e.g.
  Italian) use the same word for both.
