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

namespace Akeeba\Extract;

/**
 * Checks whether a newer version of Akeeba Extract is available.
 *
 * The update information is published to the CDN as a small JSON document
 * describing the latest stable release: its {@code version}, {@code infoURL}
 * (the GitHub release page) and {@code download} URL.
 *
 * To avoid hammering the CDN, the fetched document is cached in a per-user
 * file and only refreshed when that file is older than 12 hours (the "last
 * fetched" timestamp is simply the file's modification time). A failed fetch
 * with no prior cache still writes an empty {@code {}} document, so a broken
 * network does not trigger a fetch on every startup.
 */
final class UpdateService
{
    /** Canonical URL the release pipeline publishes the update information to. */
    public const UPDATE_URL = 'https://cdn.akeeba.com/updates/akeeba-extract.json';

    /** Refresh the cached information at most once every 12 hours. */
    private const MAX_AGE = 12 * 60 * 60;

    /** Network timeout (seconds) for the update-check request. */
    private const TIMEOUT = 5;

    public function __construct(
        private readonly string $currentVersion,
        private readonly string $cacheFile,
        private readonly string $updateUrl = self::UPDATE_URL,
    ) {}

    /**
     * Returns the update status, refreshing the cache from the CDN when stale.
     *
     * @return array{available: bool, version: string|null, infoURL: string|null, download: string|null}
     */
    public function status(): array
    {
        return $this->evaluate($this->cachedOrFresh());
    }

    /**
     * Reads the cached update information, fetching a fresh copy when the cache
     * is missing or older than {@see MAX_AGE}.
     *
     * @return array<array-key, mixed>
     */
    private function cachedOrFresh(): array
    {
        if (is_file($this->cacheFile)) {
            $age = time() - (int) @filemtime($this->cacheFile);

            if ($age >= 0 && $age < self::MAX_AGE) {
                return $this->readCache();
            }
        }

        return $this->fetch();
    }

    /**
     * Fetches the update information from the CDN (best-effort).
     *
     * On any failure it falls back to a previously-cached copy; if there is none,
     * it writes an empty {@code {}} document so the 12-hour back-off applies to
     * failed attempts too.
     *
     * @return array<array-key, mixed>
     */
    private function fetch(): array
    {
        $body = $this->httpGet($this->updateUrl);

        if ($body !== null) {
            $data = json_decode($body, true);

            if (is_array($data)) {
                $this->writeCache($body);

                return $data;
            }
        }

        if (is_file($this->cacheFile)) {
            return $this->readCache();
        }

        // No cache and the fetch failed: record the attempt with an empty document.
        $this->writeCache('{}');

        return [];
    }

    /**
     * Performs a best-effort GET request, returning the response body or null
     * on any failure (never throws).
     */
    private function httpGet(string $url): ?string
    {
        $headers = [
            'Accept: application/json',
            'User-Agent: AkeebaExtract/' . $this->currentVersion,
        ];

        try {
            if (function_exists('curl_init')) {
                $ch = curl_init($url);

                if ($ch === false) {
                    return null;
                }

                curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
                curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
                curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true);
                curl_setopt($ch, CURLOPT_TIMEOUT, self::TIMEOUT);

                $response = curl_exec($ch);
                $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);

                // No curl_close(): it is a deprecated no-op since PHP 8.0/8.5;
                // the CurlHandle is freed automatically when $ch goes out of scope.

                if ($response !== false && is_string($response) && $httpCode === 200) {
                    return $response;
                }

                return null;
            }

            $context = stream_context_create([
                'http' => [
                    'method'        => 'GET',
                    'header'        => implode("\r\n", $headers),
                    'timeout'       => self::TIMEOUT,
                    'ignore_errors' => true,
                ],
                'ssl' => [
                    'verify_peer'      => true,
                    'verify_peer_name' => true,
                ],
            ]);

            $response = @file_get_contents($url, false, $context);

            return $response !== false ? $response : null;
        } catch (\Throwable) {
            return null;
        }
    }

    /** @return array<array-key, mixed> */
    private function readCache(): array
    {
        $raw = @file_get_contents($this->cacheFile);

        if ($raw === false) {
            return [];
        }

        $data = json_decode($raw, true);

        return is_array($data) ? $data : [];
    }

    private function writeCache(string $json): void
    {
        $dir = \dirname($this->cacheFile);

        if (!is_dir($dir)) {
            @mkdir($dir, 0700, true);
        }

        @file_put_contents($this->cacheFile, $json);
    }

    /**
     * Turns the cached update document into the status returned to the SPA.
     *
     * @param array<array-key, mixed> $info
     *
     * @return array{available: bool, version: string|null, infoURL: string|null, download: string|null}
     */
    private function evaluate(array $info): array
    {
        $version  = isset($info['version']) && is_string($info['version']) ? trim($info['version']) : '';
        $infoURL  = isset($info['infoURL']) && is_string($info['infoURL']) ? $info['infoURL'] : '';
        $download = isset($info['download']) && is_string($info['download']) ? $info['download'] : '';

        $available = $version !== '' && version_compare($version, $this->currentVersion, '>');

        return [
            'available' => $available,
            'version'   => $available ? $version : null,
            'infoURL'   => $available && $infoURL !== '' ? $infoURL : null,
            'download'  => $available && $download !== '' ? $download : null,
        ];
    }
}
