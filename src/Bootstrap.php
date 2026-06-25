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
 * Bootstrap the vendored Kickstart engine for a plain CLI/desktop context.
 *
 * This file must be require'd exactly once. It:
 *   1. Defines any constants the engine needs that are normally set by masterSetup()
 *      or the web controller (which we do NOT use).
 *   2. Loads every engine file in dependency order.
 *
 * Web-global safety notes
 * -----------------------
 * - getQueryParam() in preamble.php references $_REQUEST but is only called by
 *   mastersetup.php / application.php — files we do not vendor — so it is never
 *   invoked on this code path.
 * - clearFileInOPCache() in preamble.php references $_SERVER['SCRIPT_FILENAME']
 *   inside a lazy static initialisation block; in CLI context PHP sets this
 *   superglobal to the entry-point script path, so the expression is safe (and
 *   OPcache is typically disabled in CLI anyway).
 * - No web globals appear at file-include time in any vendored engine file.
 */

// ---------------------------------------------------------------------------
// Constants expected by the engine when the web controller is absent
// ---------------------------------------------------------------------------

/**
 * Signals that we are running as "kickstart.php" (the stand-alone extractor)
 * rather than as the embedded "restore.php" inside a CMS.
 *
 * Effect in factory.php (lines 143-162): when KICKSTART is defined the factory
 * does NOT append the long list of Joomla/WordPress restoration.php paths to
 * the skip_files list.  Those skip entries are irrelevant for a generic
 * archive extractor and should be absent so the archive is written verbatim.
 * Step 03 will further pass skip_files => [] and rename_files => [] in its
 * $configOverride to ensure a completely faithful extraction.
 */
if (!defined('KICKSTART'))
{
	define('KICKSTART', 1);
}

/**
 * Root directory used by the engine as a fallback destination when
 * kickstart.setup.destdir has not been set.  We point it at the current
 * working directory; it will be overridden via AKFactory::set() before
 * every extraction anyway.
 */
if (!defined('KSROOTDIR'))
{
	define('KSROOTDIR', getcwd());
}

// ---------------------------------------------------------------------------
// Engine files — loaded in strict dependency order
// ---------------------------------------------------------------------------
$__engineDir = dirname(__DIR__) . '/engine';

// 1. Global constants (AK_STATE_*, DS, _AKEEBA_IS_WINDOWS, KSROOTDIR, KSLANGDIR,
//    helper functions: akstringlen, aksubstr, getQueryParam, debugMsg,
//    clearFileInOPCache).
require_once $__engineDir . '/preamble.php';

// 2. Base object (AKAbstractObject — error/warning queue).
require_once $__engineDir . '/abstract.object.php';

// 3. Abstract part (AKAbstractPart — tick() state machine; extends AKAbstractObject).
require_once $__engineDir . '/abstract.part.php';

// 4. Observer contract (AKAbstractPartObserver — must exist before AKText shim
//    and before any concrete observer or unarchiver that attach observers).
require_once $__engineDir . '/abstract.part.observer.php';

// 5. AKText shim (used by all unarchivers for error messages; must be available
//    before any class that calls AKText::_() or AKText::sprintf() is defined —
//    i.e. before the unarchiver and postproc files).
require_once $__engineDir . '/AKText.php';

// 6. Timer (AKCoreTimer — extends AKAbstractObject; references AKFactory::get()
//    only at construction time, which is after factory.php is loaded; safe here
//    because the class body is merely declared, not instantiated).
require_once $__engineDir . '/core.timer.php';

// 7. Hash utility shim (AKUtilsHash — used by encryption.aes.php for MD5 caching;
//    PHP 8.4 deprecates standalone md5() so the shim routes through hash() instead).
require_once $__engineDir . '/utils.hash.php';

// 8. Encryption layer (interface → abstract adapter → concrete adapters).
require_once $__engineDir . '/encryption.interface.php';  // AKEncryptionAESAdapterInterface
require_once $__engineDir . '/encryption.adapter.php';    // AKEncryptionAESAdapterAbstract
require_once $__engineDir . '/encryption.aes.php';        // AKEncryptionAES
require_once $__engineDir . '/encryption.openssl.php';    // AKEncryptionAESAdapterOpenSSL
require_once $__engineDir . '/encryption.mcrypt.php';     // AKEncryptionAESAdapterMcrypt

// 9. Post-processor abstract + direct implementation.
require_once $__engineDir . '/abstract.postproc.php';     // AKAbstractPostproc
require_once $__engineDir . '/postproc.direct.php';       // AKPostprocDirect

// 10. Abstract unarchiver (AKAbstractUnarchiver — extends AKAbstractPart;
//    depends on AKAbstractPostproc and AKText).
require_once $__engineDir . '/abstract.unarchiver.php';

// 11. Concrete unarchivers.
require_once $__engineDir . '/unarchiver.jpa.php';        // AKUnarchiverJPA
require_once $__engineDir . '/unarchiver.jps.php';        // AKUnarchiverJPS (needs AKEncryptionAES)
require_once $__engineDir . '/unarchiver.zip.php';        // AKUnarchiverZIP

// 12. Null observer (AKPartNullObserver — extends AKAbstractPartObserver).
require_once $__engineDir . '/null.observer.php';

// 13. Factory (AKFactory — instantiates all of the above; must be last so every
//     class it references is already declared).
require_once $__engineDir . '/factory.php';

unset($__engineDir);
