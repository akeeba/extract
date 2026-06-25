#!/usr/bin/env php
<?php
/**
 * Akeeba Extract
 * A cross-platform desktop application to extract Akeeba Backup archives (JPA, JPS, ZIP)
 *
 * @package   akeeba-extract
 * @copyright Copyright (c)2026 Nicholas K. Dionysopoulos / Akeeba Ltd
 * @license   GNU General Public License version 3, or later
 */

/**
 * Headless extraction harness.
 *
 * Usage:
 *   php bin/extract-cli.php <archive> <destination> [password]
 *
 * Arguments:
 *   archive       Absolute or relative path to the .jpa / .jps / .zip file.
 *   destination   Directory to extract into (will be created if absent).
 *   password      Optional decryption password (JPS archives only).
 *
 * Exit codes:
 *   0  Extraction completed successfully.
 *   1  Error (bad arguments, unreadable archive, engine failure, etc.).
 *
 * Dependencies are loaded via plain require — no Composer autoloader needed.
 */

// ---------------------------------------------------------------------------
// Ensure we run in CLI mode
// ---------------------------------------------------------------------------
if (PHP_SAPI !== 'cli')
{
	fwrite(STDERR, "This script must be run from the command line.\n");
	exit(1);
}

// ---------------------------------------------------------------------------
// Parse arguments
// ---------------------------------------------------------------------------
if ($argc < 3)
{
	fwrite(STDERR, "Usage: php bin/extract-cli.php <archive> <destination> [password]\n");
	exit(1);
}

$archive     = $argv[1];
$destination = $argv[2];
$password    = $argv[3] ?? null;

// Resolve relative paths
if (!str_starts_with($archive, '/') && !str_starts_with($archive, '\\'))
{
	$archive = getcwd() . DIRECTORY_SEPARATOR . $archive;
}

if (!str_starts_with($destination, '/') && !str_starts_with($destination, '\\'))
{
	$destination = getcwd() . DIRECTORY_SEPARATOR . $destination;
}

// ---------------------------------------------------------------------------
// Bootstrap the engine and load our classes
// ---------------------------------------------------------------------------
$__root = dirname(__DIR__);

require $__root . '/src/Bootstrap.php';
require $__root . '/src/ProgressObserver.php';
require $__root . '/src/ExtractorService.php';

// ---------------------------------------------------------------------------
// Create the destination directory if needed
// ---------------------------------------------------------------------------
if (!is_dir($destination))
{
	if (!mkdir($destination, 0755, true) && !is_dir($destination))
	{
		fwrite(STDERR, "ERROR: Cannot create destination directory: {$destination}\n");
		exit(1);
	}
}

// ---------------------------------------------------------------------------
// Run the extraction
// ---------------------------------------------------------------------------
$service = new \Akeeba\Extract\ExtractorService();

try
{
	$service->begin($archive, $destination, $password);
}
catch (\RuntimeException $e)
{
	fwrite(STDERR, "ERROR: " . $e->getMessage() . "\n");
	exit(1);
}

$result      = null;
$lastLine    = '';

do
{
	$result = $service->step();

	// Build a compact progress line: overwrite the previous one
	$line = sprintf(
		"\r%3d%%  files: %d  out: %s",
		$result['percent'],
		$result['files'],
		formatBytes($result['bytesOut'])
	);

	// Pad to overwrite any longer previous line
	$padding = max(0, strlen($lastLine) - strlen($line));
	echo $line . str_repeat(' ', $padding);
	$lastLine = $line;

} while (!$result['done']);

// Move to the next line after the progress output
echo "\n";

// ---------------------------------------------------------------------------
// Report outcome
// ---------------------------------------------------------------------------
if ($result['error'] !== '')
{
	fwrite(STDERR, "ERROR: " . $result['error'] . "\n");

	if (!empty($result['warnings']))
	{
		foreach ($result['warnings'] as $warning)
		{
			fwrite(STDERR, "WARNING: {$warning}\n");
		}
	}

	exit(1);
}

// Print a concise summary
echo sprintf(
	"Done.  %d file(s)  %s compressed  %s uncompressed\n",
	$result['files'],
	formatBytes($result['bytesIn']),
	formatBytes($result['bytesOut'])
);

if (!empty($result['warnings']))
{
	foreach ($result['warnings'] as $warning)
	{
		echo "WARNING: {$warning}\n";
	}
}

exit(0);

// ---------------------------------------------------------------------------
// Helper: human-readable byte size
// ---------------------------------------------------------------------------
function formatBytes(float $bytes): string
{
	if ($bytes < 1024)
	{
		return number_format($bytes) . ' B';
	}

	if ($bytes < 1024 * 1024)
	{
		return number_format($bytes / 1024, 1) . ' KB';
	}

	if ($bytes < 1024 * 1024 * 1024)
	{
		return number_format($bytes / (1024 * 1024), 2) . ' MB';
	}

	return number_format($bytes / (1024 * 1024 * 1024), 2) . ' GB';
}
