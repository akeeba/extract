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
 * A tiny persistent key–value store backed by a JSON file.
 *
 * Lives alongside the cached update document in the per-user configuration
 * directory (see {@see Paths::configDir()}). Currently used only for the
 * interface-language override, but deliberately generic so other preferences can
 * be added without new plumbing.
 *
 * The file is read lazily and written on every set(); a missing, empty or
 * corrupt file is treated as "no settings" rather than an error.
 */
final class Settings
{
    /** Loaded settings, or null until first accessed. @var array<string, mixed>|null */
    private ?array $data = null;

    /** Absolute path to the JSON file, resolved lazily so Paths runs only when needed. */
    private ?string $file = null;

    public function __construct(?string $file = null)
    {
        $this->file = $file;
    }

    /**
     * Return a stored value, or $default when the key is absent.
     *
     * @param  string  $key      The setting name.
     * @param  mixed   $default  Returned when the key is not present.
     *
     * @return mixed
     */
    public function get(string $key, mixed $default = null): mixed
    {
        $this->load();

        return $this->data[$key] ?? $default;
    }

    /**
     * Store a value and persist it immediately.
     *
     * @param  string  $key    The setting name.
     * @param  mixed   $value  The value to store (must be JSON-serialisable).
     *
     * @return void
     */
    public function set(string $key, mixed $value): void
    {
        $this->load();
        $this->data[$key] = $value;
        $this->save();
    }

    /** Resolve, and lazily create, the backing file path. */
    private function path(): string
    {
        if ($this->file === null) {
            $this->file = Paths::configDir() . \DIRECTORY_SEPARATOR . 'settings.json';
        }

        return $this->file;
    }

    /** Load the JSON file into memory once. A bad or missing file yields an empty set. */
    private function load(): void
    {
        if ($this->data !== null) {
            return;
        }

        $this->data = [];

        $path = $this->path();

        if (!is_file($path) || !is_readable($path)) {
            return;
        }

        $raw = @file_get_contents($path);

        if ($raw === false || $raw === '') {
            return;
        }

        $decoded = json_decode($raw, true);

        if (is_array($decoded)) {
            $this->data = $decoded;
        }
    }

    /** Write the in-memory settings back to disk (best-effort). */
    private function save(): void
    {
        $json = json_encode(
            $this->data ?? [],
            JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE
        );

        if ($json === false) {
            return;
        }

        @file_put_contents($this->path(), $json);
    }
}
