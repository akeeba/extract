# Conventions

- PHP 8.4, `boson-php/*` pinned to `^0.19` (pre-1.0 — the API breaks between minor versions).
- Indentation is **not uniform**: `engine/`, `ExtractorService.php`, and `ProgressObserver.php` use
  tabs with Allman braces; the newer `src/` files use 4 spaces. Match the file you are editing.
- Commit subjects are short and imperative, often area-prefixed (`Windows: …`, `Build: …`, `Inno: …`),
  with a body explaining *why* when the change is non-obvious, and a `Signed-off-by` trailer.
- `.plans/` is gitignored internal scratch, not part of the deliverable.
