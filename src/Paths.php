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
 * Resolves OS-appropriate, writable application directories.
 *
 * The application stores the cached update-check document inside the
 * per-user application configuration directory for the current platform.
 */
final class Paths
{
    private const APP_DIR_NAME = 'Akeeba Extract';

    /**
     * Absolute path to the per-user configuration directory.
     *
     * macOS:   ~/Library/Application Support/Akeeba Extract
     * Windows: %APPDATA%\Akeeba Extract  (falls back to %USERPROFILE%\AppData\Roaming\Akeeba Extract)
     * Linux:   $XDG_CONFIG_HOME/akeeba-extract  (falls back to ~/.config/akeeba-extract)
     */
    public static function configDir(): string
    {
        $dir = self::resolveBaseConfigDir();

        if (!is_dir($dir)) {
            @mkdir($dir, 0700, true);
        }

        return $dir;
    }

    /** Absolute path to the cached update-information file. */
    public static function updatesFile(): string
    {
        return self::configDir() . \DIRECTORY_SEPARATOR . 'updates.json';
    }

    private static function resolveBaseConfigDir(): string
    {
        if (\PHP_OS_FAMILY === 'Darwin') {
            return self::home() . '/Library/Application Support/' . self::APP_DIR_NAME;
        }

        if (\PHP_OS_FAMILY === 'Windows') {
            $appDataEnv = getenv('APPDATA');
            $appData    = $appDataEnv !== false ? $appDataEnv : (self::home() . '\\AppData\\Roaming');

            return rtrim($appData, '\\/') . '\\' . self::APP_DIR_NAME;
        }

        // Linux and other *nix
        $xdgEnv = getenv('XDG_CONFIG_HOME');
        $xdg    = $xdgEnv !== false ? $xdgEnv : (self::home() . '/.config');

        return rtrim($xdg, '/') . '/akeeba-extract';
    }

    private static function home(): string
    {
        $home = getenv('HOME');

        if ($home !== false) {
            return rtrim($home, '\\/');
        }

        // Windows fallback
        $profile = getenv('USERPROFILE');

        if ($profile !== false) {
            return rtrim($profile, '\\/');
        }

        return sys_get_temp_dir();
    }
}
