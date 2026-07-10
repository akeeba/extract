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

namespace Akeeba\Extract\I18n;

use Akeeba\Extract\Settings;
use AKText;

/**
 * Resolves the interface language and feeds the matching catalogue to the engine's
 * {@see \AKText} translation table.
 *
 * The effective language is, in order of precedence:
 *   1. the user's explicit override (a tag, when not "auto");
 *   2. the operating-system language, if it is one we ship;
 *   3. en-GB (the canonical fallback).
 *
 * The detection algorithm is ported from Grafida's I18n\LanguageService; the
 * translation back-end is AKText (INI files) rather than joomla/language. Strings
 * live in one `language/<tag>/<tag>.ini` per language; en-GB is always loaded
 * first as the fallback, so a translation may omit any key it does not (yet)
 * provide.
 */
final class LanguageService
{
    public const DEFAULT_TAG = 'en-GB';
    public const AUTO        = 'auto';
    public const SETTING_KEY = 'ui_language';

    /** Translation key each language file carries to name itself in its own tongue. */
    private const ENDONYM_KEY = 'EXTRACT_LANGUAGE_ENDONYM';

    private ?string $resolvedTag = null;

    private bool $loaded = false;

    /** @var array<string, string>|null Cached tag => endonym map. */
    private ?array $available = null;

    /** @var list<string>|null Cached list of shipped language tags. */
    private ?array $availableTags = null;

    public function __construct(
        private readonly Settings $settings,
        private readonly string $basePath,
    ) {}

    /**
     * Resolve the language and load its strings into AKText.
     *
     * Idempotent: repeated calls are a no-op until {@see setOverride()} forces a
     * re-resolution.
     */
    public function load(): void
    {
        if ($this->loaded) {
            return;
        }

        $akText = AKText::getInstance();
        $akText->resetTranslation();

        // en-GB is the fallback base under every language.
        $akText->loadTranslationFile($this->iniPath(self::DEFAULT_TAG));

        $tag = $this->currentTag();

        if ($tag !== self::DEFAULT_TAG) {
            $akText->loadTranslationFile($this->iniPath($tag));
        }

        $this->loaded = true;
    }

    /** The language tag actually in use after applying the precedence rules. */
    public function currentTag(): string
    {
        if ($this->resolvedTag === null) {
            $this->resolvedTag = $this->resolveTag();
        }

        return $this->resolvedTag;
    }

    /**
     * The languages the application ships, as an ordered tag => endonym map.
     *
     * Discovered at runtime by scanning the language directory: every
     * `<tag>/<tag>.ini` is a shipped language, and its EXTRACT_LANGUAGE_ENDONYM
     * key names it in its own tongue (so adding a translation needs no code
     * change). The default language sorts first, the rest by endonym.
     *
     * @return array<string, string>
     */
    public function available(): array
    {
        if ($this->available !== null) {
            return $this->available;
        }

        $map = [];

        foreach ($this->availableTags() as $tag) {
            $map[$tag] = $this->readEndonym($tag) ?? $tag;
        }

        uksort($map, function (string $a, string $b) use ($map): int {
            if ($a === self::DEFAULT_TAG) {
                return -1;
            }

            if ($b === self::DEFAULT_TAG) {
                return 1;
            }

            return strcoll($map[$a], $map[$b]);
        });

        return $this->available = $map;
    }

    /** The stored override ("auto" when auto-detecting). */
    public function override(): string
    {
        return $this->settings->get(self::SETTING_KEY, self::AUTO) ?? self::AUTO;
    }

    /** Sets and persists the language override (use self::AUTO for auto-detect). */
    public function setOverride(string $tag): void
    {
        $tag = $tag === self::AUTO || $this->isAvailable($tag) ? $tag : self::AUTO;
        $this->settings->set(self::SETTING_KEY, $tag);

        // Force re-resolution and a reload on the next load()/translate().
        $this->resolvedTag = null;
        $this->loaded      = false;
        $this->load();
    }

    /** Translates a language key (delegates to the loaded AKText table). */
    public function translate(string $key): string
    {
        $this->load();

        return AKText::_($key);
    }

    /**
     * Resolve a set of keys to a flat map, for shipping to the front-end.
     *
     * @param list<string> $keys Keys to resolve.
     *
     * @return array<string, string>
     */
    public function strings(array $keys): array
    {
        $this->load();

        $out = [];

        foreach ($keys as $key) {
            $out[$key] = AKText::_($key);
        }

        return $out;
    }

    /**
     * The whole loaded catalogue plus selection metadata, ready for the front-end.
     *
     * The caller json_encodes this and injects it as `window.__akeebaLang`, so the
     * UI can translate itself from `window.__akeebaLang.strings[KEY]`.
     *
     * @return array{tag: string, override: string, endonym: string, available: array<string, string>, strings: array<string, string>}
     */
    public function catalog(): array
    {
        $this->load();

        $tag = $this->currentTag();

        return [
            'tag'       => $tag,
            'override'  => $this->override(),
            'endonym'   => $this->available()[$tag] ?? $tag,
            'available' => $this->available(),
            'strings'   => AKText::getInstance()->getStrings(),
        ];
    }

    private function resolveTag(): string
    {
        $override = $this->override();

        if ($override !== self::AUTO && $this->isAvailable($override)) {
            return $override;
        }

        $detected = $this->detectOsLanguage();

        return $detected !== null && $this->isAvailable($detected) ? $detected : self::DEFAULT_TAG;
    }

    /**
     * Best-effort detection of the OS language as one of our tags (e.g. "el-GR").
     */
    private function detectOsLanguage(): ?string
    {
        $lcAll      = getenv('LC_ALL');
        $lcMessages = getenv('LC_MESSAGES');
        $lang       = getenv('LANG');
        $raw        = $lcAll !== false && $lcAll !== '' ? $lcAll
            : ($lcMessages !== false && $lcMessages !== '' ? $lcMessages
            : ($lang !== false && $lang !== '' ? $lang : ''));

        if ($raw === '' && \function_exists('locale_get_default')) {
            $raw = (string) locale_get_default();
        }

        if ($raw === '') {
            return null;
        }

        // Normalise e.g. "el_GR.UTF-8" or "el-GR" -> "el-GR".
        $raw   = str_replace('_', '-', $raw);
        $raw   = explode('.', $raw)[0];
        $parts = explode('-', $raw);

        if (\count($parts) < 2) {
            // Match by language part alone (e.g. "fr" -> "fr-FR").
            $langPart = strtolower($parts[0]);

            foreach ($this->availableTags() as $tag) {
                if (str_starts_with(strtolower($tag), $langPart . '-')) {
                    return $tag;
                }
            }

            return null;
        }

        $candidate = strtolower($parts[0]) . '-' . strtoupper($parts[1]);

        return $this->isAvailable($candidate) ? $candidate : null;
    }

    /** Whether the given tag is one of the languages the application ships. */
    private function isAvailable(string $tag): bool
    {
        return \in_array($tag, $this->availableTags(), true);
    }

    /**
     * Discovers the shipped language tags by scanning the language directory for
     * `<tag>/<tag>.ini` files. en-GB is always present (the canonical source).
     *
     * @return list<string>
     */
    private function availableTags(): array
    {
        if ($this->availableTags !== null) {
            return $this->availableTags;
        }

        $tags = [self::DEFAULT_TAG];

        $dirs = glob($this->basePath . '/language/*', \GLOB_ONLYDIR);

        foreach ($dirs === false ? [] : $dirs as $dir) {
            $tag = basename($dir);

            if ($tag === self::DEFAULT_TAG || \in_array($tag, $tags, true)) {
                continue;
            }

            // Only count it as a shipped language if it actually carries our strings.
            if (is_file($this->iniPath($tag))) {
                $tags[] = $tag;
            }
        }

        return $this->availableTags = $tags;
    }

    /** Absolute path to a language's `<tag>/<tag>.ini` catalogue. */
    private function iniPath(string $tag): string
    {
        return $this->basePath . '/language/' . $tag . '/' . $tag . '.ini';
    }

    /**
     * Reads a language's self-name (endonym) straight from its INI file, without
     * loading the whole catalogue. Returns null when the file or key is missing.
     */
    private function readEndonym(string $tag): ?string
    {
        $file = $this->iniPath($tag);

        $handle = @fopen($file, 'r');

        if ($handle === false) {
            return null;
        }

        try {
            while (($line = fgets($handle)) !== false) {
                if (!str_starts_with(ltrim($line), self::ENDONYM_KEY)) {
                    continue;
                }

                if (preg_match('/^\s*' . self::ENDONYM_KEY . '\s*=\s*"(.*)"\s*$/u', $line, $m) === 1) {
                    return $m[1];
                }
            }
        } finally {
            fclose($handle);
        }

        return null;
    }
}
