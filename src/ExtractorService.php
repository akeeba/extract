<?php
/**
 * Akeeba Extract
 * A cross-platform desktop application to extract Akeeba Backup archives (JPA, JPS, ZIP)
 *
 * @package   akeeba-extract
 * @copyright Copyright (c)2026 Nicholas K. Dionysopoulos / Akeeba Ltd
 * @license   GNU General Public License version 3, or later
 */

namespace Akeeba\Extract;

/**
 * High-level extraction service wrapping the Kickstart engine.
 *
 * This class provides a simple begin/step/cancel API that is intentionally
 * free of any GUI or Boson references so it can be used from the CLI test
 * harness, unit tests, and the Boson binding layer alike.
 *
 * Typical usage:
 *
 * ```php
 * $svc = new ExtractorService();
 * $svc->begin('/path/to/archive.jpa', '/output/dir');
 *
 * do {
 *     $result = $svc->step();
 * } while (!$result['done']);
 *
 * if ($result['error'] !== '') {
 *     // handle failure
 * }
 * ```
 *
 * The engine is stateful and single-threaded. Do not call begin() again
 * without either finishing the previous run or calling cancel() first.
 */
final class ExtractorService
{
	// -------------------------------------------------------------------------
	// Private state
	// -------------------------------------------------------------------------

	/** @var \AKAbstractUnarchiver|null The active engine instance */
	private ?\AKAbstractUnarchiver $engine = null;

	/** @var ProgressObserver|null The active progress observer */
	private ?ProgressObserver $observer = null;

	/** @var float Combined size in bytes of all archive part files on disk */
	private float $totalBytes = 0.0;

	/** @var bool True once begin() has been called and before the run ends */
	private bool $started = false;

	/** @var bool Set by cancel() to short-circuit the next step() call */
	private bool $cancelled = false;

	/** @var int Last reported progress percentage (monotonic non-decreasing) */
	private int $lastPercent = 0;

	// -------------------------------------------------------------------------
	// Public API
	// -------------------------------------------------------------------------

	/**
	 * Initialise the engine for a new extraction run.
	 *
	 * Must be called once before the first step(). Calling begin() on an
	 * already-running extraction implicitly cancels it and starts fresh.
	 *
	 * @param  string       $archive      Absolute path to the primary archive file (.jpa / .jps / .zip).
	 * @param  string       $destination  Absolute path to the output directory (created if absent).
	 * @param  string|null  $password     Decryption password for JPS archives; null / '' for plain archives.
	 *
	 * @throws \RuntimeException  If $archive does not exist or is not readable.
	 */
	public function begin(string $archive, string $destination, ?string $password = null): void
	{
		// --- Validate input ---------------------------------------------------

		if ($archive === '')
		{
			throw new \RuntimeException('Please select an archive file before starting extraction.');
		}

		if (!file_exists($archive))
		{
			throw new \RuntimeException(
				sprintf('Archive file not found: "%s". Please check the path and try again.', basename($archive))
			);
		}

		if (!is_readable($archive))
		{
			throw new \RuntimeException(
				sprintf('Cannot read archive file "%s". Check file permissions and try again.', basename($archive))
			);
		}

		// Verify it has a supported archive extension
		$ext = strtolower(pathinfo($archive, PATHINFO_EXTENSION));

		if (!in_array($ext, ['jpa', 'jps', 'zip'], true))
		{
			throw new \RuntimeException(
				sprintf(
					'"%s" does not appear to be a supported archive (expected .jpa, .jps, or .zip).',
					basename($archive)
				)
			);
		}

		// Validate destination: create it if absent, check writable
		if ($destination === '')
		{
			throw new \RuntimeException('Please select an output folder before starting extraction.');
		}

		if (!is_dir($destination))
		{
			// Attempt to create it; suppress the PHP warning — we check the return value instead
			if (!@mkdir($destination, 0755, true) && !is_dir($destination))
			{
				throw new \RuntimeException(
					sprintf(
						'Output folder "%s" does not exist and could not be created. '
						. 'Please select a different folder or create it manually.',
						$destination
					)
				);
			}
		}

		if (!is_writable($destination))
		{
			throw new \RuntimeException(
				sprintf(
					'Output folder "%s" is not writable. '
					. 'Please choose a folder you have write access to.',
					$destination
				)
			);
		}

		// --- Reset any previous run ------------------------------------------

		\AKFactory::nuke();

		$this->engine      = null;
		$this->observer    = null;
		$this->started     = false;
		$this->cancelled   = false;
		$this->lastPercent = 0;

		// --- Configure the factory -------------------------------------------

		\AKFactory::set('kickstart.enabled', true);
		\AKFactory::set('kickstart.setup.sourcefile', $archive);
		\AKFactory::set('kickstart.setup.destdir', $destination);
		\AKFactory::set('kickstart.setup.targetpath', $destination);
		\AKFactory::set('kickstart.procengine', 'direct');
		\AKFactory::set('kickstart.jps.password', (string) $password);

		// Timer tuning: keep each tick to ~1 s so the UI stays responsive
		\AKFactory::set('kickstart.tuning.max_exec_time', 1);
		\AKFactory::set('kickstart.tuning.run_time_bias', 75);

		// --- Build the engine with faithful-extraction overrides -------------
		//
		// The Kickstart defaults rename / skip several Joomla-specific files and
		// ignore certain directories. For a generic extractor we override all of
		// those lists to empty so the archive is written verbatim.

		$this->engine = \AKFactory::getUnarchiver([
			'rename_files'      => [],
			'skip_files'        => [],
			'ignoredirectories' => [],
		]);

		// --- Attach the progress observer ------------------------------------

		$this->observer = new ProgressObserver();
		$this->engine->attach($this->observer);

		// --- Calculate total archive size on disk ----------------------------
		//
		// For multi-part archives the earlier parts are named .j01, .j02, … (or
		// .z01, .z02, … for ZIP) and the last part keeps the original extension
		// (.jpa / .jps / .zip). We glob for all of them and sum their sizes.

		$this->totalBytes = $this->computeTotalBytes($archive);

		// --- Mark as started -------------------------------------------------

		$this->started = true;
	}

	/**
	 * Perform one extraction chunk (one engine tick).
	 *
	 * The engine is time-bounded: each tick runs for approximately 1 second
	 * (controlled by `kickstart.tuning.max_exec_time`). The UI layer should
	 * call step() in a tight loop (or via JS `setTimeout`) until `done` is true.
	 *
	 * The `percent` value is monotonically non-decreasing and is forced to 100
	 * when the engine finishes without error.
	 *
	 * @return array{
	 *   percent:    int,
	 *   files:      int,
	 *   bytesIn:    float,
	 *   bytesOut:   float,
	 *   totalBytes: float,
	 *   done:       bool,
	 *   error:      string,
	 *   warnings:   array<int, string>,
	 * }
	 */
	public function step(): array
	{
		// --- Handle cancelled state ------------------------------------------

		if ($this->cancelled)
		{
			\AKFactory::nuke();
			$this->started = false;

			return $this->buildResult(
				percent:   $this->lastPercent,
				done:      true,
				error:     'cancelled',
				warnings:  [],
				hasRun:    false
			);
		}

		// --- Safety guard (begin() not called) --------------------------------

		if (!$this->started || $this->engine === null)
		{
			return $this->buildResult(
				percent:  0,
				done:     true,
				error:    'ExtractorService::begin() must be called before step().',
				warnings: [],
				hasRun:   false
			);
		}

		// --- Perform one engine tick -----------------------------------------

		// Reset the timer so this tick gets a fresh ~1 s budget.
		\AKFactory::getTimer()->resetTime();

		$this->engine->tick();

		$ret = $this->engine->getStatusArray();

		// --- Calculate progress percentage -----------------------------------

		$percent = $this->computePercent();

		// Engine returns false (not '') when there is no error (end([]) === false).
		// Use !empty() so both false and '' are treated as "no error".
		$hasError = !empty($ret['Error']);

		// If this tick finished the run (no error), force 100 %
		$done = ($ret['HasRun'] === false) || $hasError;

		if ($done && !$hasError)
		{
			$percent = 100;
		}

		// Enforce monotonic non-decreasing guarantee
		$percent           = max($percent, $this->lastPercent);
		$this->lastPercent = $percent;

		// Cast error to string: false → '', string → itself
		$errorStr = $hasError ? (string) $ret['Error'] : '';

		return $this->buildResult(
			percent:  $percent,
			done:     $done,
			error:    $errorStr,
			warnings: array_values($ret['Warnings'] ?? []),
			hasRun:   $ret['HasRun'] ?? true
		);
	}

	/**
	 * Signal that the current extraction should be aborted.
	 *
	 * The next call to step() will return `done = true` with an empty error
	 * string. The engine state is nuked to free resources.
	 */
	public function cancel(): void
	{
		$this->cancelled = true;
	}

	// -------------------------------------------------------------------------
	// Private helpers
	// -------------------------------------------------------------------------

	/**
	 * Sum the on-disk sizes of all archive parts.
	 *
	 * Naming convention:
	 *   - Multi-part JPA/JPS: `archive.j01`, `archive.j02`, …, `archive.jpa` / `.jps`
	 *   - Multi-part ZIP:     `archive.z01`, `archive.z02`, …, `archive.zip`
	 *   - Single-part:        just the primary file.
	 *
	 * @param  string  $primaryFile  Absolute path to the `.jpa` / `.jps` / `.zip` file.
	 * @return float                 Total size in bytes (>= 0).
	 */
	private function computeTotalBytes(string $primaryFile): float
	{
		$dir      = dirname($primaryFile);
		$basename = pathinfo($primaryFile, PATHINFO_FILENAME); // without extension
		$ext      = strtolower(pathinfo($primaryFile, PATHINFO_EXTENSION));

		// Determine part-file letter: JPA/JPS use 'j', ZIP uses 'z'
		$partLetter = ($ext === 'zip') ? 'z' : 'j';

		// Glob for all numbered parts (e.g. archive.j01, archive.z02, …)
		$pattern = $dir . DIRECTORY_SEPARATOR . $basename . '.' . $partLetter . '[0-9][0-9]';
		$parts   = glob($pattern) ?: [];

		// Add the primary file itself
		$parts[] = $primaryFile;

		$total = 0.0;

		foreach ($parts as $part)
		{
			if (is_readable($part))
			{
				$total += (float) filesize($part);
			}
		}

		return $total;
	}

	/**
	 * Calculate the current progress as an integer percentage [0, 100].
	 *
	 * Percentage = compressed bytes consumed ÷ total archive bytes on disk × 100.
	 * Clamped to [0, 100].
	 *
	 * @return int
	 */
	private function computePercent(): int
	{
		if ($this->totalBytes <= 0.0 || $this->observer === null)
		{
			return 0;
		}

		return (int) min(100, round($this->observer->compressedTotal / $this->totalBytes * 100));
	}

	/**
	 * Build the standard step()-result array.
	 *
	 * @param  int                   $percent
	 * @param  bool                  $done
	 * @param  string                $error
	 * @param  array<int, string>    $warnings
	 * @param  bool                  $hasRun    Raw HasRun value from the engine (unused but kept for clarity).
	 * @return array
	 */
	private function buildResult(
		int    $percent,
		bool   $done,
		string $error,
		array  $warnings,
		bool   $hasRun
	): array {
		return [
			'percent'    => $percent,
			'files'      => $this->observer?->filesProcessed ?? 0,
			'bytesIn'    => (float) ($this->observer?->compressedTotal ?? 0.0),
			'bytesOut'   => (float) ($this->observer?->uncompressedTotal ?? 0.0),
			'totalBytes' => $this->totalBytes,
			'done'       => $done,
			'error'      => $error,
			'warnings'   => $warnings,
		];
	}
}
