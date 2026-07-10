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
 * AKText — the engine's translation table.
 *
 * This is a trimmed, INI-driven port of Kickstart's full text.php. It keeps the
 * calling convention the vendored engine relies on — AKText::_() for a language
 * key and AKText::sprintf() for a parameterised one — but drops Kickstart's
 * embedded per-language PHP arrays and its HTTP_ACCEPT_LANGUAGE browser
 * detection. Language selection is the job of {@see \Akeeba\Extract\I18n\LanguageService},
 * which resolves a tag from the operating system (or a stored override) and
 * feeds the matching INI file(s) to loadTranslationFile().
 *
 * The strings table starts empty. LanguageService loads en-GB.ini first (the
 * canonical fallback) and then the resolved language's INI over it, so a missing
 * key in a translation transparently falls back to English, and an unresolved
 * key falls back to the key itself.
 */
class AKText extends AKAbstractObject
{
	/**
	 * The loaded key => translation table.
	 *
	 * @var  array<string, string>
	 */
	private $strings = [];

	/**
	 * Singleton accessor.
	 *
	 * @return  AKText  The global AKText instance.
	 */
	public static function &getInstance()
	{
		static $instance;

		if (!is_object($instance))
		{
			$instance = new AKText();
		}

		return $instance;
	}

	/**
	 * Translate a language key.
	 *
	 * The key is upper-cased and a single leading underscore stripped before the
	 * lookup, matching Kickstart's convention. Unknown keys fall back to a defined
	 * PHP constant of the same name, and finally to the raw string, so an error
	 * key such as ERR_CORRUPT_ARCHIVE is still human-readable if no catalogue is
	 * loaded.
	 *
	 * @param   string  $string  The language key.
	 *
	 * @return  string
	 */
	public static function _($string)
	{
		$text = self::getInstance();

		$key = strtoupper($string);
		$key = substr($key, 0, 1) == '_' ? substr($key, 1) : $key;

		if (isset($text->strings[$key]))
		{
			return $text->strings[$key];
		}

		if (defined($string))
		{
			return constant($string);
		}

		return $string;
	}

	/**
	 * Translate a language key and substitute values into it via sprintf().
	 *
	 * The first argument is the key (translated via _()); the remaining arguments
	 * are the sprintf() substitutions, so callers write, e.g.,
	 * AKText::sprintf('COULDNT_CREATE_DIR', $path).
	 *
	 * @param   string  $key  The language key / format template.
	 *
	 * @return  string
	 */
	public static function sprintf($key)
	{
		$args = func_get_args();

		if (count($args) === 0)
		{
			return '';
		}

		$args[0] = self::_($args[0]);

		return @call_user_func_array('sprintf', $args);
	}

	/**
	 * Merge an INI translation file over the current strings table.
	 *
	 * Later files win, so loading en-GB.ini and then a translation's INI gives the
	 * translation precedence with an English fallback for any key it omits.
	 * A missing or unreadable file is a silent no-op.
	 *
	 * @param   string  $absoluteFilePath  Absolute path to the INI file.
	 *
	 * @return  void
	 */
	public function loadTranslationFile($absoluteFilePath)
	{
		if (empty($absoluteFilePath) || !@is_file($absoluteFilePath) || !@is_readable($absoluteFilePath))
		{
			return;
		}

		$temp = self::parse_ini_file($absoluteFilePath, false);

		if (empty($temp) || !is_array($temp))
		{
			return;
		}

		$this->strings = array_merge($this->strings, $temp);
	}

	/**
	 * Merge default strings underneath the current table (existing keys win).
	 *
	 * @param   array<string, string>  $stringList  Defaults to seed.
	 *
	 * @return  void
	 */
	public function addDefaultLanguageStrings($stringList = [])
	{
		if (!is_array($stringList) || empty($stringList))
		{
			return;
		}

		$this->strings = array_merge($stringList, $this->strings);
	}

	/**
	 * Empty the strings table.
	 *
	 * @return  void
	 */
	public function resetTranslation()
	{
		$this->strings = [];
	}

	/**
	 * The loaded key => translation table.
	 *
	 * @return  array<string, string>
	 */
	public function getStrings()
	{
		return $this->strings;
	}

	/**
	 * Dump the loaded strings as KEY=VALUE lines (diagnostics).
	 *
	 * @return  string
	 */
	public function dumpLanguage()
	{
		$out = '';

		foreach ($this->strings as $key => $value)
		{
			$out .= "$key=$value\n";
		}

		return $out;
	}

	/**
	 * Export the loaded strings as a JavaScript object body.
	 *
	 * Produces `'KEY': 'VALUE', …` (without the surrounding braces), safely
	 * escaped, for injection into the front-end so the UI can translate itself.
	 *
	 * @return  string
	 */
	public function asJavascript()
	{
		$out = '';

		foreach ($this->strings as $key => $value)
		{
			$key   = addcslashes($key, "\\'\"");
			$value = addcslashes($value, "\\'\"");

			if (!empty($out))
			{
				$out .= ",\n";
			}

			$out .= "'$key':\t'$value'";
		}

		return $out;
	}

	/**
	 * Parse an INI file into an associative array.
	 *
	 * A hand-rolled parser (from Kickstart, credited to asohn ~at~ aircanopy) used
	 * instead of PHP's parse_ini_file() so the catalogue format — KEY="Value" with
	 * ;; comments — parses identically across PHP builds regardless of INI-scanner
	 * mode.
	 *
	 * @param   string  $file              Filename to process (or raw data if $rawdata).
	 * @param   bool    $process_sections  True to also process INI sections.
	 * @param   bool    $rawdata           If true, $file contains raw INI data, not a path.
	 *
	 * @return  array  An associative array of keys and values.
	 */
	public static function parse_ini_file($file, $process_sections = false, $rawdata = false)
	{
		$process_sections = ($process_sections !== true) ? false : true;

		if (!$rawdata)
		{
			$ini = file($file);
		}
		else
		{
			$file = str_replace("\r", "", $file);
			$ini  = explode("\n", $file);
		}

		if (!is_array($ini) || count($ini) == 0)
		{
			return [];
		}

		$sections = [];
		$values   = [];
		$result   = [];
		$globals  = [];
		$i        = 0;

		foreach ($ini as $line)
		{
			$line = trim($line);
			$line = str_replace("\t", " ", $line);

			// Comments
			if (!preg_match('/^[a-zA-Z0-9[]/', $line))
			{
				continue;
			}

			// Sections
			if ($line[0] == '[')
			{
				$tmp        = explode(']', $line);
				$sections[] = trim(substr($tmp[0], 1));
				$i++;
				continue;
			}

			// Key-value pair
			$lineParts = explode('=', $line, 2);

			if (count($lineParts) != 2)
			{
				continue;
			}

			$key   = trim($lineParts[0]);
			$value = trim($lineParts[1]);
			unset($lineParts);

			if (strstr($value, ";"))
			{
				$tmp = explode(';', $value);

				if (count($tmp) == 2)
				{
					if ((($value[0] != '"') && ($value[0] != "'")) ||
						preg_match('/^".*"\s*;/', $value) || preg_match('/^".*;[^"]*$/', $value) ||
						preg_match("/^'.*'\s*;/", $value) || preg_match("/^'.*;[^']*$/", $value)
					)
					{
						$value = $tmp[0];
					}
				}
				else
				{
					if ($value[0] == '"')
					{
						$value = preg_replace('/^"(.*)".*/', '$1', $value);
					}
					elseif ($value[0] == "'")
					{
						$value = preg_replace("/^'(.*)'.*/", '$1', $value);
					}
					else
					{
						$value = $tmp[0];
					}
				}
			}

			$value = trim($value);
			$value = trim($value, "'\"");

			if ($i == 0)
			{
				if (substr($line, -1, 2) == '[]')
				{
					$globals[$key][] = $value;
				}
				else
				{
					$globals[$key] = $value;
				}
			}
			else
			{
				if (substr($line, -1, 2) == '[]')
				{
					$values[$i - 1][$key][] = $value;
				}
				else
				{
					$values[$i - 1][$key] = $value;
				}
			}
		}

		for ($j = 0; $j < $i; $j++)
		{
			if ($process_sections === true)
			{
				if (isset($sections[$j]) && isset($values[$j]))
				{
					$result[$sections[$j]] = $values[$j];
				}
			}
			else
			{
				if (isset($values[$j]))
				{
					$result[] = $values[$j];
				}
			}
		}

		return $result + $globals;
	}
}
