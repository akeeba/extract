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
 * Single source of truth for the application's identity and version.
 *
 * VERSION is stamped from the topmost CHANGELOG entry by build/tasks/set-version.php
 * before every compile; the build/packaging scripts read it back out of this file.
 */
final class App
{
    /** Human-readable application name. */
    public const NAME = 'Akeeba Extract';

    /** Application version (semantic versioning). */
    public const VERSION = '0.1';

    /** Copyright line. */
    public const COPYRIGHT = 'Copyright © 2026 Nicholas K. Dionysopoulos / Akeeba Ltd';
}
