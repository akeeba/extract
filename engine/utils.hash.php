<?php
/**
 * Akeeba Restore
 * An AJAX-powered archive extraction library for JPA, JPS and ZIP archives
 *
 * @package   restore
 * @copyright Copyright (c)2024-2025 Nicholas K. Dionysopoulos / Akeeba Ltd
 * @license   GNU General Public License version 3, or later
 */

/**
 * PHP 8.4+ workaround for standalone MD5 and SHA-1 functions.
 *
 * PHP 8.4 deprecates the standalone md5(), md5_file(), sha1(), and sha1_file() functions. This trait creates shims
 * which use the hash() and hash_file() functions instead where available.
 *
 * IMPORTANT! PHP 7.4 made the ext/hash extension mandatory. These shims are here only as a backwards compatibility aid.
 * Eventually, we need to remove them, replacing their use by the direct use of hash() and hash_file().
 *
 * @deprecated 9.0
 */
abstract class AKUtilsHash
{
	/**
	 * @deprecated 9.0 Use hash() instead
	 */
	public static function md5($string, $binary = false)
	{
		static $shouldUseHash = null;

		if ($shouldUseHash === null)
		{
			$shouldUseHash = function_exists('hash')
			                 && function_exists('hash_algos')
			                 && in_array('md5', hash_algos());
		}

		return $shouldUseHash ? hash('md5', $string, $binary) : md5($string, $binary);
	}
}