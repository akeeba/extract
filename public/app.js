/**
 * Akeeba Extract
 * A cross-platform desktop application to extract Akeeba Backup archives (JPA, JPS, ZIP)
 *
 * @package   akeeba-extract
 * @copyright Copyright (c)2026 Nicholas K. Dionysopoulos / Akeeba Ltd
 * @license   GNU General Public License version 3, or later
 */

'use strict';

(function () {
  // ── DOM references ──────────────────────────────────────────────────────
  var archivePath     = document.getElementById('archive-path');
  var outputDir       = document.getElementById('output-dir');
  var passwordField   = document.getElementById('password-field');
  var archivePass     = document.getElementById('archive-password');
  var btnBrowseArc    = document.getElementById('btn-browse-archive');
  var btnBrowseOut    = document.getElementById('btn-browse-output');
  var btnStart        = document.getElementById('btn-start');
  var btnCancel       = document.getElementById('btn-cancel');
  var progressBar     = document.getElementById('extract-progress');
  var statusLine      = document.getElementById('status-line');
  var resultSuccess   = document.getElementById('result-success');
  var resultSuccessMsg = document.getElementById('result-success-msg');
  var resultCancelled = document.getElementById('result-cancelled');
  var resultError     = document.getElementById('result-error');
  var btnOpenFolder   = document.getElementById('btn-open-folder');
  var warningsArea    = document.getElementById('warnings-area');
  var warningsSummary = document.getElementById('warnings-summary');
  var warningsList    = document.getElementById('warnings-list');

  // ── State ───────────────────────────────────────────────────────────────
  var running = false;

  /**
   * The last successfully used output directory, remembered in-memory for the
   * session so subsequent extractions default to the same location.
   */
  var lastOutputDir = null;

  // All input / button controls that must be locked during extraction.
  var lockableInputs   = [archivePath, outputDir, archivePass];
  var lockableButtons  = [btnBrowseArc, btnBrowseOut];

  // ── Helpers ─────────────────────────────────────────────────────────────

  /**
   * Archive types this application can open directly.
   *
   * Multi-part pieces (.j01, .j02, … / .z01, .z02, …) are NOT in this list on
   * purpose: the engine discovers and reads them automatically once the main
   * archive (.jpa / .jps / .zip) is selected. The native file picker greys out
   * (or, on some platforms, fails to filter) non-matching files, so we enforce
   * the rule here as well — see isAllowedArchive().
   */
  var ALLOWED_ARCHIVE_EXT = ['jpa', 'jps', 'zip'];

  /** Lower-cased file extension of a path, or '' when there is none. */
  function fileExt(path) {
    // Strip any query/fragment, trailing slashes, then the directory portion.
    var clean = String(path || '').replace(/[?#].*$/, '').replace(/[/\\]+$/, '');
    var base  = clean.replace(/^.*[/\\]/, '');
    var dot   = base.lastIndexOf('.');
    return dot >= 0 ? base.slice(dot + 1).toLowerCase() : '';
  }

  /** True when the path looks like an archive we can open directly. */
  function isAllowedArchive(path) {
    return ALLOWED_ARCHIVE_EXT.indexOf(fileExt(path)) !== -1;
  }

  /**
   * Adopt an archive path from any source — the Browse picker, a drag-and-drop
   * onto the window, or a path passed on the command line. Validates the
   * extension, fills the archive field, reveals the password field for JPS, and
   * defaults the output folder to the archive's directory.
   */
  function setArchive(path) {
    if (!path) return;

    // Don't disturb an extraction in progress.
    if (running) return;

    if (!isAllowedArchive(path)) {
      showError(
        'Please choose a .jpa, .jps, or .zip archive. ' +
        'Multi-part pieces such as .j01 or .z01 are detected automatically — ' +
        'select the main archive file instead.'
      );
      return;
    }

    clearResults();
    archivePath.value = path;
    updatePasswordVisibility();

    // Auto-fill the output dir with the remembered last dir or the archive's dir.
    /* global defaultDir */
    defaultDir(path).then(function (dir) {
      if (outputDir.value.trim() === '') {
        outputDir.value = lastOutputDir || dir || '';
      }
      updateStartButton();
    }).catch(function () {
      updateStartButton();
    });
  }

  // Exposed so the PHP side can hand us a dropped file's path (see index.php,
  // the WebViewNavigating handler).
  window.__akeebaApplyArchive = setArchive;

  /** Show or hide the password field based on the archive extension. */
  function updatePasswordVisibility() {
    var path = archivePath.value || '';
    var isJps = fileExt(path) === 'jps';
    if (isJps) {
      passwordField.classList.remove('hidden');
    } else {
      passwordField.classList.add('hidden');
      archivePass.value = '';
    }
  }

  /** Enable / disable the Start button based on form validity. */
  function updateStartButton() {
    var hasArchive = archivePath.value.trim() !== '';
    var hasOutput  = outputDir.value.trim() !== '';
    btnStart.disabled = !hasArchive || !hasOutput || running;
  }

  /**
   * Switch the UI into "running" or "idle" mode.
   * When on=true: lock all inputs, show Cancel, hide Start.
   * When on=false: unlock all inputs, hide Cancel, re-evaluate Start.
   */
  function setRunning(on) {
    running = on;
    lockableInputs.forEach(function (el) { el.disabled = on; });
    lockableButtons.forEach(function (el) { el.disabled = on; });
    btnStart.disabled = on;

    if (on) {
      btnCancel.classList.remove('hidden');
    } else {
      btnCancel.classList.add('hidden');
    }

    if (!on) {
      updateStartButton();
    }
  }

  /** Update the progress bar and status line from a step() result. */
  function updateProgress(p) {
    var pct = (typeof p.percent === 'number') ? p.percent : 0;
    progressBar.value = pct;

    var files = (typeof p.files === 'number') ? p.files : 0;
    var msg   = pct + '%';
    if (files > 0) {
      msg += ' — ~' + files + ' file' + (files !== 1 ? 's' : '');
    }
    statusLine.textContent = 'Extracting… ' + msg;
  }

  /**
   * Render engine warnings into the collapsible <details> area.
   * Hides the area if there are no warnings.
   */
  function showWarnings(warnings) {
    if (!warnings || warnings.length === 0) {
      warningsArea.classList.add('hidden');
      return;
    }

    warningsList.innerHTML = '';
    warnings.forEach(function (w) {
      var li = document.createElement('li');
      li.textContent = w;
      warningsList.appendChild(li);
    });
    warningsSummary.textContent = 'Warnings (' + warnings.length + ')';
    warningsArea.classList.remove('hidden');
  }

  /** Show the success result area and the "Open output folder" button. */
  function showDone(p) {
    setRunning(false);
    progressBar.value = 100;
    statusLine.textContent = '';

    var files = (typeof p.files === 'number') ? p.files : 0;
    var msg = 'Done';
    if (files > 0) {
      msg += ' — approximately ' + files + ' file' + (files !== 1 ? 's' : '') + ' extracted.';
    } else {
      msg += '.';
    }

    resultSuccessMsg.textContent = msg;
    resultSuccess.classList.add('is-visible');
    resultSuccess.classList.remove('hidden');
    resultCancelled.classList.add('hidden');
    resultCancelled.classList.remove('is-visible');
    resultError.classList.add('hidden');
    resultError.classList.remove('is-visible');

    // Show "Open Output Folder" button if we know the destination
    var dest = outputDir.value.trim();
    if (dest) {
      btnOpenFolder.classList.remove('hidden');
      // Remember for session
      lastOutputDir = dest;
    } else {
      btnOpenFolder.classList.add('hidden');
    }

    showWarnings(p.warnings);
  }

  /** Show the cancelled banner. */
  function showCancelled() {
    setRunning(false);
    progressBar.value = 0;
    statusLine.textContent = '';

    resultCancelled.classList.add('is-visible');
    resultCancelled.classList.remove('hidden');
    resultSuccess.classList.add('hidden');
    resultSuccess.classList.remove('is-visible');
    resultError.classList.add('hidden');
    resultError.classList.remove('is-visible');
    warningsArea.classList.add('hidden');
    btnOpenFolder.classList.add('hidden');
  }

  /** Show the error result area. */
  function showError(err) {
    setRunning(false);
    progressBar.value = 0;
    statusLine.textContent = '';

    var msg = (typeof err === 'string') ? err
            : (err && err.message) ? err.message
            : String(err);

    resultError.textContent = msg;
    resultError.classList.add('is-visible');
    resultError.classList.remove('hidden');
    resultSuccess.classList.add('hidden');
    resultSuccess.classList.remove('is-visible');
    resultCancelled.classList.add('hidden');
    resultCancelled.classList.remove('is-visible');
    warningsArea.classList.add('hidden');
    btnOpenFolder.classList.add('hidden');
  }

  /** Clear result areas for a fresh run. */
  function clearResults() {
    resultSuccess.classList.remove('is-visible');
    resultSuccess.classList.add('hidden');
    resultCancelled.classList.remove('is-visible');
    resultCancelled.classList.add('hidden');
    resultError.classList.remove('is-visible');
    resultError.classList.add('hidden');
    resultSuccessMsg.textContent = '';
    resultError.textContent      = '';
    progressBar.value            = 0;
    statusLine.textContent       = '';
    warningsArea.classList.add('hidden');
    btnOpenFolder.classList.add('hidden');
  }

  // ── Step pump ───────────────────────────────────────────────────────────
  /**
   * One tick of the extraction pump.
   * Calls extractor.step(), updates UI, then yields back to the browser
   * via requestAnimationFrame before the next tick.
   * This keeps the window responsive while extraction runs.
   */
  function pump() {
    /* global extractor */
    extractor.step().then(function (p) {
      // Surface any accumulated warnings even on partial steps
      if (p.warnings && p.warnings.length > 0) {
        showWarnings(p.warnings);
      }

      if (p.error) {
        // Special sentinel value for cancel
        if (p.error === 'cancelled') {
          showCancelled();
          return;
        }
        showError(p.error);
        return;
      }

      if (p.done) {
        showDone(p);
        return;
      }

      updateProgress(p);
      requestAnimationFrame(pump);
    }).catch(function (err) {
      showError(err);
    });
  }

  // ── Event handlers ───────────────────────────────────────────────────────

  btnBrowseArc.addEventListener('click', function () {
    // The native picker should restrict the choice to .jpa/.jps/.zip, but not
    // every platform honours the filter (it may merely grey out other files, or
    // ignore the filter entirely), so setArchive() re-validates the selection.
    /* global pickArchive */
    pickArchive().then(setArchive).catch(function () {});
  });

  btnBrowseOut.addEventListener('click', function () {
    // Start the picker from the current value, the last used dir, or the archive's parent
    var start = outputDir.value.trim() || lastOutputDir || null;
    if (!start && archivePath.value.trim()) {
      start = archivePath.value.trim().replace(/[^/\\]*$/, '').replace(/[/\\]$/, '') || null;
    }
    /* global pickOutputDir */
    pickOutputDir(start || null).then(function (path) {
      if (!path) return;
      outputDir.value = path;
      lastOutputDir = path;
      updateStartButton();
    }).catch(function () {});
  });

  archivePath.addEventListener('input', function () {
    updatePasswordVisibility();
    updateStartButton();
  });

  outputDir.addEventListener('input', function () {
    updateStartButton();
  });

  btnStart.addEventListener('click', function () {
    var archive  = archivePath.value.trim();
    var dest     = outputDir.value.trim();
    var password = archivePass.value; // may be empty string

    if (!archive || !dest) {
      showError('Please select an archive file and an output folder.');
      return;
    }

    if (!isAllowedArchive(archive)) {
      showError(
        'The selected file is not a supported archive. ' +
        'Choose a .jpa, .jps, or .zip file.'
      );
      return;
    }

    clearResults();
    setRunning(true);
    statusLine.textContent = 'Starting…';

    extractor.begin(archive, dest, password || null).then(function (result) {
      if (!result.ok) {
        showError(result.error || 'Failed to start extraction.');
        return;
      }
      // Kick off the step pump
      requestAnimationFrame(pump);
    }).catch(function (err) {
      showError(err);
    });
  });

  btnCancel.addEventListener('click', function () {
    // Disable the Cancel button immediately to prevent double-clicks
    btnCancel.disabled = true;
    statusLine.textContent = 'Cancelling…';
    extractor.cancel().catch(function () {});
    // The pump will observe the `cancelled` sentinel on the next step() call
  });

  btnOpenFolder.addEventListener('click', function () {
    var dest = outputDir.value.trim();
    if (dest) {
      /* global openFolder */
      openFolder(dest).catch(function () {});
    }
  });

  // ── Drag-and-drop ────────────────────────────────────────────────────────
  // saucer's WebView registers no native file-drop handler and does NOT
  // navigate to a dropped file, so we have to capture the drop in the page and
  // recover the file's path from the drag data. The 'drop' event only fires if
  // we preventDefault() on dragenter/dragover, so we do.

  /** Turn a file:// URL or raw string into a local filesystem path, or null. */
  function toLocalPath(s) {
    s = String(s || '').trim();
    if (!s) return null;

    if (/^file:\/\//i.test(s)) {
      var rest = s.replace(/^file:\/\//i, '');
      // Empty host → "/path"; otherwise drop the "host" before the first "/".
      if (rest.charAt(0) !== '/') {
        var slash = rest.indexOf('/');
        rest = slash >= 0 ? rest.slice(slash) : '/' + rest;
      }
      try { rest = decodeURIComponent(rest); } catch (e) {}
      if (/^\/[A-Za-z]:/.test(rest)) rest = rest.slice(1); // Windows /C:/… → C:/…
      return rest;
    }

    // Already an absolute POSIX or Windows path?
    if (s.charAt(0) === '/' || /^[A-Za-z]:[\\/]/.test(s)) return s;

    return null;
  }

  /** Best-effort extraction of a dropped file's path from a DataTransfer. */
  function localPathFromDragData(dt) {
    if (!dt) return null;

    var candidates = [];

    // text/uri-list (RFC 2483): one URI per line, '#' lines are comments.
    try {
      (dt.getData('text/uri-list') || '').split(/\r?\n/).forEach(function (ln) {
        ln = ln.trim();
        if (ln && ln.charAt(0) !== '#') candidates.push(ln);
      });
    } catch (e) {}

    // text/plain sometimes carries the path or a file:// URL.
    try {
      var plain = (dt.getData('text/plain') || '').trim();
      if (plain) candidates.push(plain);
    } catch (e) {}

    // Some WebViews expose a real filesystem path on the File object itself.
    if (dt.files && dt.files.length && dt.files[0].path) {
      candidates.push(dt.files[0].path);
    }

    for (var i = 0; i < candidates.length; i++) {
      var p = toLocalPath(candidates[i]);
      if (p) return p;
    }
    return null;
  }

  function setDragHint(on) {
    document.body.classList.toggle('drag-over', !!on);
  }

  window.addEventListener('dragenter', function (e) {
    e.preventDefault();
    setDragHint(true);
  });

  window.addEventListener('dragover', function (e) {
    e.preventDefault(); // required so the 'drop' event will fire
    if (e.dataTransfer) {
      try { e.dataTransfer.dropEffect = 'copy'; } catch (x) {}
    }
    setDragHint(true);
  });

  window.addEventListener('dragleave', function (e) {
    // relatedTarget is null only when the pointer leaves the window entirely.
    if (!e.relatedTarget) setDragHint(false);
  });

  window.addEventListener('drop', function (e) {
    e.preventDefault();
    setDragHint(false);

    var dt   = e.dataTransfer;
    var path = localPathFromDragData(dt);

    if (path) {
      setArchive(path);
      return;
    }

    // A file was dropped but the WebView did not reveal its location. This is
    // the case on macOS (WKWebView hands the page only the file's contents, not
    // its path), so we can't open it by drag-and-drop there. Point the user at
    // the alternatives, which work everywhere.
    if (dt && dt.files && dt.files.length > 0) {
      showError(
        'Drag-and-drop isn’t available on this system: its WebView doesn’t tell ' +
        'the app where the dropped file lives. Please use the Browse… button, or ' +
        'open the archive directly from your file manager.'
      );
    }
  });

  // ── Initialise ──────────────────────────────────────────────────────────
  updateStartButton();

  // Drag-and-drop can't work on macOS (WKWebView withholds the dropped file's
  // path), so don't advertise it there.
  var dragHintEl = document.getElementById('drag-hint');
  if (dragHintEl && /Mac/i.test(navigator.userAgent || '')) {
    dragHintEl.classList.add('hidden');
  }

  /**
   * If the app was launched with an archive path (file association or CLI
   * argument), adopt it once the binding is available. Bindings may attach a
   * tick after the script runs, so retry briefly.
   */
  function loadInitialArchive(attempts) {
    /* global initialArchive */
    if (typeof initialArchive !== 'function') {
      if (attempts > 0) {
        setTimeout(function () { loadInitialArchive(attempts - 1); }, 80);
      }
      return;
    }
    initialArchive().then(function (path) {
      if (path) setArchive(path);
    }).catch(function () {});
  }
  loadInitialArchive(20);

})();
