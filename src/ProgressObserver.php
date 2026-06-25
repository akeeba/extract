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
 * Progress observer for the Kickstart extraction engine.
 *
 * Attached to the unarchiver via `$engine->attach($observer)`. On each
 * `startfile` message the engine emits, this observer accumulates the
 * compressed bytes consumed from the archive and the uncompressed bytes
 * written to disk. These counters drive the progress-percentage calculation
 * in ExtractorService.
 *
 * The engine keys observers by their string representation
 * (see abstract.part.php:321-323), so __toString() must return a stable,
 * unique string — we return the fully-qualified class name.
 */
final class ProgressObserver extends \AKAbstractPartObserver
{
	/** @var int Number of files whose extraction has started */
	public int $filesProcessed = 0;

	/** @var float Total compressed bytes consumed from the archive so far */
	public float $compressedTotal = 0.0;

	/** @var float Total uncompressed bytes written to disk so far */
	public float $uncompressedTotal = 0.0;

	/**
	 * Whether to record the path/type of every entry the engine visits.
	 *
	 * Switched on by ExtractorService only for a dry-run scan (used to build the
	 * "Pick a file or directory" tree). It is left off for real extractions so
	 * we don't accumulate a potentially huge in-memory list for no reason.
	 *
	 * @var bool
	 */
	public bool $collectFileList = false;

	/**
	 * Collected archive entries when $collectFileList is true.
	 *
	 * Each element is `['path' => string, 'type' => 'file'|'dir'|'link']`.
	 *
	 * @var array<int, array{path: string, type: string}>
	 */
	public array $fileList = [];

	/**
	 * Called by the engine whenever it has a status update to report.
	 *
	 * We only care about `startfile` messages. All others are silently ignored.
	 * Guards mirror those in the reference RestorationObserver in
	 * kickstart/source/buildscripts/cli_test.php:61-93.
	 *
	 * @param  object  $object   The engine part that fired the notification.
	 * @param  mixed   $message  The message object (or non-object — must guard).
	 */
	public function update($object, $message): void
	{
		// Guard: the engine sometimes passes non-object messages
		if (!is_object($message))
		{
			return;
		}

		// Guard: message must have a `type` property
		if (!array_key_exists('type', get_object_vars($message)))
		{
			return;
		}

		if ($message->type !== 'startfile')
		{
			return;
		}

		$this->filesProcessed++;
		$this->compressedTotal   += (float) $message->content->compressed;
		$this->uncompressedTotal += (float) $message->content->uncompressed;

		// During a dry-run scan, remember each entry so the UI can build a
		// pick-list tree. content->file is the archive-relative path; content->type
		// is 'file', 'dir', or 'link' (added to the engine's startfile message).
		if ($this->collectFileList)
		{
			$path = (string) ($message->content->file ?? '');

			if ($path !== '')
			{
				$this->fileList[] = [
					'path' => $path,
					'type' => (string) ($message->content->type ?? 'file'),
				];
			}
		}
	}

	/**
	 * The engine stores observers in an associative array keyed by their
	 * string form (`$this->observers["$obs"] = $obs`). Returning the FQCN
	 * ensures the key is stable and unique across the process lifetime.
	 */
	public function __toString(): string
	{
		return self::class;
	}
}
