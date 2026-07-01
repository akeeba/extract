## Akeeba Extract 0.1

The first public release of **Akeeba Extract** — a cross-platform desktop application that
extracts **Akeeba Backup** archives (JPA, encrypted JPS, and ZIP).

### Highlights

* Extracts JPA, JPS (AES-encrypted, password-protected), and ZIP archives.
* Handles multi-part archives automatically (`.jpa` + `.j01`, `.j02`, …).
* **Selective extraction:** extract only the files you need with glob patterns, or use the
  built-in archive browser to pick files and folders from a tree.
* **Skip most errors:** optionally keep going past files that cannot be written or corrupt
  entries, instead of aborting the whole run.
* Native file/folder pickers and a live progress bar.
* Clean error messages for common failure cases: corrupt archive, wrong password, unwritable
  destination, missing multi-part file, user cancel.
* Single self-contained binary per platform — no PHP installation required by end users.

> [!IMPORTANT]
> This is a Technology Preview release. Use at your own risk.
