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
 * Minimal AKText shim for Akeeba Extract.
 *
 * The full Kickstart text.php (110 KB) is not vendored. The engine calls
 * AKText::_() for untranslated error-message keys and AKText::sprintf() for
 * parameterised variants. This shim returns the raw key (for _()) or a
 * vsprintf-formatted string with the key as the format template (for sprintf()),
 * which is readable enough in an error context without requiring a translation
 * database.
 */
class AKText
{
	/**
	 * Returns a (possibly translated) string for the given language key.
	 *
	 * In this shim the key itself is returned verbatim, which is acceptable
	 * because error keys such as ERR_CORRUPT_ARCHIVE are already human-readable.
	 *
	 * @param   string  $key  The language key.
	 *
	 * @return  string
	 */
	public static function _($key)
	{
		return $key;
	}

	/**
	 * Returns a sprintf-formatted string using the language key as the format.
	 *
	 * Additional arguments beyond $key are substituted into the format string
	 * via vsprintf(), matching the calling convention used by the engine files.
	 *
	 * @param   string  $key   The language key / format string.
	 * @param   mixed   ...$args  Values to substitute.
	 *
	 * @return  string
	 */
	public static function sprintf($key, ...$args)
	{
		if (empty($args))
		{
			return $key;
		}

		return vsprintf($key, $args);
	}
}
