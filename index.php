<?php
/**
 * Akeeba Extract
 * A cross-platform desktop application to extract Akeeba Backup archives (JPA, JPS, ZIP)
 *
 * @package   akeeba-extract
 * @copyright Copyright (c)2026 Nicholas K. Dionysopoulos / Akeeba Ltd
 * @license   GNU General Public License version 3, or later
 */

declare(strict_types=1);

require __DIR__ . '/vendor/autoload.php';
require __DIR__ . '/src/Bootstrap.php';

use Boson\Application;
use Boson\ApplicationCreateInfo;
use Boson\Component\Http\Response;
use Boson\WebView\Api\Schemes\Event\SchemeRequestReceived;
use Boson\WebView\WebViewCreateInfo;
use Boson\Window\WindowCreateInfo;

// ---------------------------------------------------------------------------
// Create the Boson application with a fixed window (560 × 440, not maximised)
// ---------------------------------------------------------------------------

$app = new Application(
    info: new ApplicationCreateInfo(
        name: 'akeeba-extract',
        schemes: ['app'],
        window: new WindowCreateInfo(
            title:     'Akeeba Extract',
            width:     580,
            height:    480,
            resizable: true,
            webview: new WebViewCreateInfo(
                contextMenu: false,
                devTools:    false,
                storage:     false,
            ),
        ),
    ),
);

// ---------------------------------------------------------------------------
// Register a custom "app://" scheme that serves files from public/
// The webview will load  app://host/index.html  (and app://host/app.css etc.)
// ---------------------------------------------------------------------------

$publicDir = __DIR__ . '/public';

$app->webview->addEventListener(
    SchemeRequestReceived::class,
    static function (SchemeRequestReceived $event) use ($publicDir): void {
        // Path component of the URL, e.g.  /index.html  or  /app.js
        $path = $event->request->url->path ?? '/index.html';

        // Normalise: strip leading slash, prevent directory traversal
        $path     = ltrim((string) $path, '/');
        $path     = str_replace(['..', "\0"], '', $path);
        $filePath = $publicDir . '/' . ($path ?: 'index.html');

        if (!is_readable($filePath)) {
            $event->response = new Response(status: 404, body: '404 Not Found');
            return;
        }

        $ext  = strtolower(pathinfo($filePath, PATHINFO_EXTENSION));
        $mime = match ($ext) {
            'html'        => 'text/html; charset=utf-8',
            'css'         => 'text/css',
            'js'          => 'application/javascript',
            'png'         => 'image/png',
            'jpg', 'jpeg' => 'image/jpeg',
            'svg'         => 'image/svg+xml',
            default       => 'application/octet-stream',
        };

        $event->response = new Response(
            status:  200,
            headers: ['Content-Type' => $mime],
            body:    file_get_contents($filePath),
        );
    }
);

// Navigate to the UI entry point via the custom scheme
$app->webview->url = 'app://host/index.html';

// ---------------------------------------------------------------------------
// Instantiate the extraction service
// ---------------------------------------------------------------------------

$service = new \Akeeba\Extract\ExtractorService();

// ---------------------------------------------------------------------------
// Register JS ↔ PHP bindings
//
// Dot notation ("extractor.begin" etc.) is supported by Boson 0.19's
// WebViewContextPacker — it creates nested window objects automatically.
//
// Every binding body is wrapped in try/catch so a thrown exception is
// returned as a structured error rather than breaking the JS Promise.
// ---------------------------------------------------------------------------

// pickArchive() → native file-open dialog; returns path string or null
$app->webview->bindings->bind(
    'pickArchive',
    static function () use ($app): ?string {
        try {
            return $app->dialog->selectFile(null, ['*.jpa', '*.jps', '*.zip']);
        } catch (\Throwable $e) {
            return null;
        }
    }
);

// pickOutputDir(start) → native folder-picker; returns path or null
$app->webview->bindings->bind(
    'pickOutputDir',
    static function (?string $start = null) use ($app): ?string {
        try {
            $start = (is_string($start) && $start !== '') ? $start : null;
            return $app->dialog->selectDirectory($start);
        } catch (\Throwable $e) {
            return null;
        }
    }
);

// defaultDir(archive) → dirname of the archive (helper for the UI)
$app->webview->bindings->bind(
    'defaultDir',
    static function (string $archive): ?string {
        try {
            $dir = dirname($archive);
            return ($dir !== '' && $dir !== '.') ? $dir : null;
        } catch (\Throwable $e) {
            return null;
        }
    }
);

// extractor.begin(archive, dest, password) → {ok: bool, error: string}
$app->webview->bindings->bind(
    'extractor.begin',
    static function (string $archive, string $dest, ?string $password = null) use ($service): array {
        try {
            $service->begin($archive, $dest, $password);
            return ['ok' => true, 'error' => ''];
        } catch (\Throwable $e) {
            return ['ok' => false, 'error' => $e->getMessage()];
        }
    }
);

// extractor.step() → the progress array from ExtractorService::step()
$app->webview->bindings->bind(
    'extractor.step',
    static function () use ($service): array {
        try {
            return $service->step();
        } catch (\Throwable $e) {
            return [
                'percent'    => 0,
                'files'      => 0,
                'bytesIn'    => 0.0,
                'bytesOut'   => 0.0,
                'totalBytes' => 0.0,
                'done'       => true,
                'error'      => $e->getMessage(),
                'warnings'   => [],
            ];
        }
    }
);

// extractor.cancel() → void (no return value needed)
$app->webview->bindings->bind(
    'extractor.cancel',
    static function () use ($service): void {
        try {
            $service->cancel();
        } catch (\Throwable) {
            // swallow
        }
    }
);

// openFolder(path) → open the folder in the native file manager
$app->webview->bindings->bind(
    'openFolder',
    static function (string $path) use ($app): void {
        try {
            $app->dialog->open($path);
        } catch (\Throwable) {
            // swallow
        }
    }
);

// ---------------------------------------------------------------------------
// Start the blocking event loop
// ---------------------------------------------------------------------------

$app->run();
