<?php
/**
 * Akeeba Restore
 * An AJAX-powered archive extraction library for JPA, JPS and ZIP archives
 *
 * @package   restore
 * @copyright Copyright (c)2008-2025 Nicholas K. Dionysopoulos / Akeeba Ltd
 * @license   GNU General Public License version 3, or later
 */

/**
 * JPA archive extraction class
 */
class AKUnarchiverJPA extends AKAbstractUnarchiver
{
	protected $archiveHeaderData = [];

	protected function readArchiveHeader()
	{
		debugMsg('Preparing to read archive header');
		// Initialize header data array
		$this->archiveHeaderData = new stdClass();

		// Open the first part
		debugMsg('Opening the first part');
		$this->nextFile();

		// Fail for unreadable files
		if ($this->fp === false)
		{
			debugMsg('Could not open the first part');

			return false;
		}

		// Fuzzy check for the start of archive.
		debugMsg('Fuzzy checking for archive signature');

		$sigFound = $this->fuzzySignatureSearch([
			'JPA',
		], 3);

		if (!$sigFound)
		{
			debugMsg('Cannot find a valid archive signature in the first 128Kb of the first part file');

			$this->setError(AKText::sprintf('ERR_INVALID_ARCHIVE_LONG', 'jpa', 'j'));

			return false;
		}

		debugMsg(sprintf('File signature found, position %d', ftell($this->fp)));

		// Read the signature
		$sig = fread($this->fp, 3);

		if ($sig != 'JPA')
		{
			// Not a JPA file
			debugMsg('Invalid archive signature');
			$this->setError(AKText::sprintf('ERR_INVALID_ARCHIVE_LONG', 'jpa', 'j'));

			return false;
		}

		// Read and parse header length
		$header_length_array = unpack('v', fread($this->fp, 2));
		$header_length       = $header_length_array[1];

		// Read and parse the known portion of header data (14 bytes)
		$bin_data    = fread($this->fp, 14);
		$header_data = unpack('Cmajor/Cminor/Vcount/Vuncsize/Vcsize', $bin_data);

		// Temporary array with all the data we read
		$temp = [
			'signature'        => $sig,
			'length'           => $header_length,
			'major'            => $header_data['major'],
			'minor'            => $header_data['minor'],
			'filecount'        => $header_data['count'],
			'uncompressedsize' => $header_data['uncsize'],
			'compressedsize'   => $header_data['csize'],
			'unknowndata'      => '',
		];

		// Load additional header data
		$rest_length = $header_length - 19;
		$junk        = '';

		while ($rest_length > 8)
		{
			// Read the extra length signature and size
			$extraSig    = fread($this->fp, 4);
			$binData     = fread($this->fp, 2);
			$extraHeader = unpack('vlength', $binData);
			$length      = $extraHeader['length'] - 2;

			$rest_length -= 6 + $length;

			switch ($extraSig)
			{
				case "\x4A\x50\x01\x01":
					$moreBinData        = fread($this->fp, $length);
					$moreExtraHeader    = unpack('vtotalParts', $moreBinData);
					$temp['totalParts'] = $moreExtraHeader['totalParts'];
					break;

				case "\x4A\x50\x01\x02":
					$moreBinData              = fread($this->fp, $length);

					// Only decode on 64-bit versions of PHP
					if (PHP_INT_SIZE >= 8)
					{
						$moreExtraHeader          = unpack('Puncompressed/Pcompressed', $moreBinData);
						$header_data['uncsize']   = $moreExtraHeader['uncompressed'];
						$header_data['csize']     = $moreExtraHeader['compressed'];
						$temp['uncompressedsize'] = $moreExtraHeader['uncompressed'];
						$temp['compressedsize']   = $moreExtraHeader['compressed'];
					}

					break;

				default:
					$moreBinData = fread($this->fp, $length);
					$junk        .= $extraSig . $binData . $moreBinData;
					break;
			}
		}

		if ($rest_length > 0)
		{
			$junk .= fread($this->fp, $rest_length);
		}
		else
		{
			$junk .= '';
		}

		// Array-to-object conversion
		foreach ($temp as $key => $value)
		{
			$this->archiveHeaderData->{$key} = $value;
		}

		debugMsg('Header data:');
		debugMsg('Length              : ' . $header_length);
		debugMsg('Major               : ' . $header_data['major']);
		debugMsg('Minor               : ' . $header_data['minor']);
		debugMsg('File count          : ' . $header_data['count']);
		debugMsg('Uncompressed size   : ' . $header_data['uncsize']);
		debugMsg('Compressed size     : ' . $header_data['csize']);
		debugMsg('Total Parts         : ' . (isset($header_data['totalParts']) ? $header_data['totalParts'] : '1'));

		$this->currentPartOffset = @ftell($this->fp);

		$this->dataReadLength = 0;

		return true;
	}

	/**
	 * Concrete classes must use this method to read the file header
	 *
	 * @return bool True if reading the file was successful, false if an error occurred or we reached end of archive
	 */
	protected function readFileHeader()
	{
		// If the current part is over, proceed to the next part please
		if ($this->isEOF(true))
		{
			debugMsg('Archive part EOF; moving to next file');
			$this->nextFile();
		}

		$this->currentPartOffset = ftell($this->fp);

		debugMsg("Reading file signature; part {$this->currentPartNumber}, offset {$this->currentPartOffset}");
		// Get and decode Entity Description Block
		$signature = fread($this->fp, 3);

		$this->fileHeader            = new stdClass();
		$this->fileHeader->timestamp = 0;

		// Check signature
		if ($signature != 'JPF')
		{
			if ($this->isEOF(true))
			{
				// This file is finished; make sure it's the last one
				$gotNextFile = $this->nextFile();

				if (!$gotNextFile && $this->getState() !== 'postrun')
				{
					debugMsg(sprintf('Cannot open file %s for part #%d', $this->archiveList[$this->currentPartNumber] ?: '(unknown)', $this->currentPartNumber));

					$this->setError(AKText::sprintf(
						'INVALID_FILE_HEADER_OFFSET_ZERO',
						$this->archiveList[$this->currentPartNumber] ?: '(unknown)',
						$this->currentPartNumber,
						'jpa',
						'j'
					));

					return false;
				}

				if (!$this->isEOF(false))
				{
					debugMsg('Invalid file signature before end of archive encountered');
					$this->setError(AKText::sprintf(
						'INVALID_FILE_HEADER',
						$this->currentPartNumber,
						$this->currentPartOffset,
						'jpa',
						'j'
					));

					return false;
				}

				// We're just finished
				return false;
			}
			else
			{
				$screwed = true;

				if (AKFactory::get('kickstart.setup.ignoreerrors', false))
				{
					debugMsg('Invalid file block signature; launching heuristic file block signature scanner');
					$screwed = !$this->heuristicFileHeaderLocator();

					if (!$screwed)
					{
						$signature = 'JPF';
					}
					else
					{
						debugMsg('Heuristics failed. Brace yourself for the imminent crash.');
					}
				}

				if ($screwed)
				{
					// This is not a file block! The archive is corrupt.
					debugMsg('Invalid file block signature');

					if (count($this->archiveList) > 1)
					{
						$this->setError(AKText::sprintf(
							'INVALID_FILE_HEADER_MULTIPART',
							$this->currentPartNumber,
							$this->currentPartOffset,
							'jpa',
							'j'
						));

						return false;
					}

					$this->setError(AKText::sprintf('INVALID_FILE_HEADER', $this->currentPartNumber, $this->currentPartOffset));

					return false;
				}
			}
		}
		// This a JPA Entity Block. Process the header.

		$isBannedFile = false;

		// Read length of EDB and of the Entity Path Data
		$length_array = unpack('vblocksize/vpathsize', fread($this->fp, 4));
		// Read the path data
		if ($length_array['pathsize'] > 0)
		{
			$file = fread($this->fp, $length_array['pathsize']);
		}
		else
		{
			$file = '';
		}

		// Handle file renaming
		$isRenamed = false;
		if (is_array($this->renameFiles) && (count($this->renameFiles) > 0))
		{
			if (array_key_exists($file, $this->renameFiles))
			{
				$file      = $this->renameFiles[$file];
				$isRenamed = true;
			}
		}

		// Handle directory renaming
		$isDirRenamed = false;
		if (is_array($this->renameDirs) && (count($this->renameDirs) > 0))
		{
			if (array_key_exists(dirname($file), $this->renameDirs))
			{
				$file         = rtrim($this->renameDirs[dirname($file)], '/') . '/' . basename($file);
				$isRenamed    = true;
				$isDirRenamed = true;
			}
		}

		// Read and parse the known data portion
		$bin_data    = fread($this->fp, 14);
		$header_data = unpack('Ctype/Ccompression/Vcompsize/Vuncompsize/Vperms', $bin_data);
		// Read any unknown data
		$restBytes = $length_array['blocksize'] - (21 + $length_array['pathsize']);

		if ($restBytes > 0)
		{
			// Start reading the extra fields
			while ($restBytes >= 4)
			{
				$extra_header_data      = fread($this->fp, 4);
				$extra_header           = unpack('vsignature/vlength', $extra_header_data);
				$restBytes              -= 4;
				$extra_header['length'] -= 4;

				if ($extra_header['length'] > 0)
				{
					switch ($extra_header['signature'])
					{
						case 256:
							// File modified timestamp
							$bindata                     = fread($this->fp, $extra_header['length']);
							$restBytes                   -= $extra_header['length'];
							$timestamps                  = unpack('Vmodified', substr($bindata, 0, 4));
							$filectime                   = $timestamps['modified'];
							$this->fileHeader->timestamp = $filectime;
							break;

						case 512:
							$bindata                   = fread($this->fp, $extra_header['length']);
							$restBytes                 -= $extra_header['length'];

							// Only decode on 64-bit versions of PHP
							if (PHP_INT_SIZE >= 8)
							{
								$sizes                     = unpack('Pclen/Punclen', $bindata);
								$header_data['compsize']   = $sizes['clen'];
								$header_data['uncompsize'] = $sizes['unclen'];
							}
							break;

						default:
							// Unknown field
							$junk      = fread($this->fp, $extra_header['length']);
							$restBytes -= $extra_header['length'];
							break;
					}
				}

			}

			if ($restBytes > 0)
			{
				$junk = fread($this->fp, $restBytes);
			}
		}

		$compressionType = $header_data['compression'];

		// Populate the return array
		$this->fileHeader->file         = $file;
		$this->fileHeader->compressed   = $header_data['compsize'];
		$this->fileHeader->uncompressed = $header_data['uncompsize'];

		switch ($header_data['type'])
		{
			case 0:
				$this->fileHeader->type = 'dir';
				break;

			case 1:
				$this->fileHeader->type = 'file';
				break;

			case 2:
				$this->fileHeader->type = 'link';
				break;
		}

		switch ($compressionType)
		{
			case 0:
				$this->fileHeader->compression = 'none';
				break;
			case 1:
				$this->fileHeader->compression = 'gzip';
				break;
			case 2:
				$this->fileHeader->compression = 'bzip2';
				break;
		}

		$this->fileHeader->permissions = $header_data['perms'];

		// Find hard-coded banned files
		if ((basename($this->fileHeader->file) == ".") || (basename($this->fileHeader->file) == ".."))
		{
			$isBannedFile = true;
		}

		// Also try to find banned files passed in class configuration
		if ((count($this->skipFiles) > 0) && (!$isRenamed))
		{
			if (in_array($this->fileHeader->file, $this->skipFiles))
			{
				$isBannedFile = true;
			}
		}

		// If we have a banned file, let's skip it
		if ($isBannedFile)
		{
			debugMsg('Skipping file ' . $this->fileHeader->file);
			// Advance the file pointer, skipping exactly the size of the compressed data
			$seekleft = $this->fileHeader->compressed;
			while ($seekleft > 0)
			{
				// Ensure that we can seek past archive part boundaries
				$curSize = @filesize($this->archiveList[$this->currentPartNumber]);
				$curPos  = @ftell($this->fp);
				$canSeek = $curSize - $curPos;
				if ($canSeek > $seekleft)
				{
					$canSeek = $seekleft;
				}
				@fseek($this->fp, $canSeek, SEEK_CUR);
				$seekleft -= $canSeek;
				if ($seekleft)
				{
					$this->nextFile();
				}
			}

			$this->currentPartOffset = @ftell($this->fp);
			$this->runState          = AK_STATE_DONE;

			return true;
		}

		// Remove the removePath, if any
		$this->fileHeader->file = $this->removePath($this->fileHeader->file);

		// Last chance to prepend a path to the filename
		if (!empty($this->addPath) && !$isDirRenamed)
		{
			$this->fileHeader->file = $this->addPath . $this->fileHeader->file;
		}

		// Get the translated path name
		$restorePerms = AKFactory::get('kickstart.setup.restoreperms', false);

		if (!$this->mustSkip())
		{
			if ($this->fileHeader->type == 'file')
			{
				// Regular file; ask the postproc engine to process its filename
				if ($restorePerms)
				{
					$this->fileHeader->realFile =
						$this->postProcEngine->processFilename($this->fileHeader->file, $this->fileHeader->permissions);
				}
				else
				{
					$this->fileHeader->realFile = $this->postProcEngine->processFilename($this->fileHeader->file);
				}
			}
			elseif ($this->fileHeader->type == 'dir')
			{
				$dir = $this->fileHeader->file;

				// Directory; just create it
				if ($restorePerms)
				{
					$this->postProcEngine->createDirRecursive($dir, $this->fileHeader->permissions);
				}
				else
				{
					$this->postProcEngine->createDirRecursive($dir, 0755);
				}

				$this->postProcEngine->processFilename(null);
			}
			else
			{
				// Symlink; do not post-process
				$this->postProcEngine->processFilename(null);
			}

			$this->createDirectory();
		}

		// Header is read
		$this->runState = AK_STATE_HEADER;

		$this->dataReadLength = 0;

		return true;
	}

	protected function heuristicFileHeaderLocator()
	{
		$ret     = false;
		$fullEOF = false;

		while (!$ret && !$fullEOF)
		{
			$this->currentPartOffset = @ftell($this->fp);

			if ($this->isEOF(true))
			{
				$this->nextFile();
			}

			if ($this->isEOF(false))
			{
				$fullEOF = true;
				continue;
			}

			// Read 512Kb
			$chunk     = fread($this->fp, 524288);
			$size_read = mb_strlen($chunk, '8bit');
			//$pos = strpos($chunk, 'JPF');
			$pos = mb_strpos($chunk, 'JPF', 0, '8bit');

			if ($pos !== false)
			{
				// We found it!
				$this->currentPartOffset += $pos + 3;
				@fseek($this->fp, $this->currentPartOffset, SEEK_SET);
				$ret = true;
			}
			else
			{
				// Not yet found :(
				$this->currentPartOffset = @ftell($this->fp);
			}
		}

		return $ret;
	}

	/**
	 * Creates the directory this file points to
	 */
	protected function createDirectory()
	{
		if ($this->mustSkip())
		{
			return true;
		}

		// Do we need to create a directory?
		if (empty($this->fileHeader->realFile))
		{
			$this->fileHeader->realFile = $this->fileHeader->file;
		}

		$lastSlash = strrpos($this->fileHeader->realFile, '/');
		$dirName   = substr($this->fileHeader->realFile, 0, $lastSlash);
		$perms     = $this->flagRestorePermissions ? $this->fileHeader->permissions : 0755;
		$ignore    = AKFactory::get('kickstart.setup.ignoreerrors', false) || $this->isIgnoredDirectory($dirName);

		if (($this->postProcEngine->createDirRecursive($dirName, $perms) == false) && (!$ignore))
		{
			$this->setError(AKText::sprintf('COULDNT_CREATE_DIR', $dirName));

			return false;
		}
		else
		{
			return true;
		}
	}

	/**
	 * Concrete classes must use this method to process file data. It must set $runState to AK_STATE_DATAREAD when
	 * it's finished processing the file data.
	 *
	 * @return bool True if processing the file data was successful, false if an error occurred
	 */
	protected function processFileData()
	{
		switch ($this->fileHeader->type)
		{
			case 'dir':
				return $this->processTypeDir();
				break;

			case 'link':
				return $this->processTypeLink();
				break;

			case 'file':
				switch ($this->fileHeader->compression)
				{
					case 'none':
						return $this->processTypeFileUncompressed();
						break;

					case 'gzip':
					case 'bzip2':
						return $this->processTypeFileCompressedSimple();
						break;

				}
				break;

			default:
				debugMsg('Unknown file type ' . $this->fileHeader->type);
				break;
		}
	}

	/**
	 * Process the file data of a directory entry
	 *
	 * @return bool
	 */
	private function processTypeDir()
	{
		// Directory entries in the JPA do not have file data, therefore we're done processing the entry
		$this->runState = AK_STATE_DATAREAD;

		return true;
	}

	/**
	 * Process the file data of a link entry
	 *
	 * @return bool
	 */
	private function processTypeLink()
	{
		$readBytes   = 0;
		$toReadBytes = 0;
		$leftBytes   = $this->fileHeader->compressed;
		$data        = '';

		while ($leftBytes > 0)
		{
			$toReadBytes     = ($leftBytes > $this->chunkSize) ? $this->chunkSize : $leftBytes;
			$mydata          = $this->fread($this->fp, $toReadBytes);
			$reallyReadBytes = akstringlen($mydata);
			$data            .= $mydata;
			$leftBytes       -= $reallyReadBytes;

			if ($reallyReadBytes < $toReadBytes)
			{
				// We read less than requested! Why? Did we hit local EOF?
				if ($this->isEOF(true) && !$this->isEOF(false))
				{
					// Yeap. Let's go to the next file
					$this->nextFile();
				}
				else
				{
					debugMsg('End of local file before reading all data with no more parts left. The archive is corrupt or truncated.');
					// Nope. The archive is corrupt
					$this->setError(AKText::_('ERR_CORRUPT_ARCHIVE'));

					return false;
				}
			}
		}

		$filename = isset($this->fileHeader->realFile) ? $this->fileHeader->realFile : $this->fileHeader->file;

		if (!$this->mustSkip())
		{
			// Try to remove an existing file or directory by the same name
			if (file_exists($filename))
			{
				@unlink($filename);
				@rmdir($filename);
			}

			// Remove any trailing slash
			if (substr($filename, -1) == '/')
			{
				$filename = substr($filename, 0, -1);
			}
			// Create the symlink - only possible within PHP context. There's no support built in the FTP protocol, so no postproc use is possible here :(
			@symlink($data, $filename);
		}

		$this->runState = AK_STATE_DATAREAD;

		return true; // No matter if the link was created!
	}

	private function processTypeFileUncompressed()
	{
		// Uncompressed files are being processed in small chunks, to avoid timeouts
		if (($this->dataReadLength == 0) && !$this->mustSkip())
		{
			// Before processing file data, ensure permissions are adequate
			$this->setCorrectPermissions($this->fileHeader->file);

			clearstatcache($this->fileHeader->file);
		}

		// Open the output file
		if (!$this->mustSkip())
		{
			$ignore =
				AKFactory::get('kickstart.setup.ignoreerrors', false) || $this->isIgnoredDirectory($this->fileHeader->file);

			if ($this->dataReadLength == 0)
			{
				$outfp = @fopen($this->fileHeader->realFile, 'w');
			}
			else
			{
				$outfp = @fopen($this->fileHeader->realFile, 'a');
			}

			// Can we write to the file?
			if ($outfp === false)
			{
				if (!$ignore)
				{
					// An error occurred
					debugMsg('Could not write to output file');
					$this->setError(AKText::sprintf('COULDNT_WRITE_FILE', $this->fileHeader->realFile));

					return false;
				}

				// "Skip most errors" is on: note the skipped file once (on its first
				// chunk) and carry on. The archive data is still consumed below so the
				// stream stays aligned; it is simply discarded.
				if ($this->dataReadLength == 0)
				{
					debugMsg('Skipping unwritable output file ' . $this->fileHeader->realFile);
					$this->setWarning(AKText::sprintf('SKIPPED_UNWRITABLE_FILE', $this->fileHeader->realFile));
				}
			}
		}

		// Does the file have any data, at all?
		if ($this->fileHeader->compressed == 0)
		{
			// No file data!
			if (!$this->mustSkip() && is_resource($outfp))
			{
				@fclose($outfp);
			}

			$this->runState = AK_STATE_DATAREAD;

			return true;
		}

		// Reference to the global timer
		$timer = AKFactory::getTimer();

		$toReadBytes = 0;
		$leftBytes   = $this->fileHeader->compressed - $this->dataReadLength;

		// Loop while there's data to read and enough time to do it
		while (($leftBytes > 0) && ($timer->getTimeLeft() > 0))
		{
			$toReadBytes          = ($leftBytes > $this->chunkSize) ? $this->chunkSize : $leftBytes;
			$data                 = $this->fread($this->fp, $toReadBytes);
			$reallyReadBytes      = akstringlen($data);
			$leftBytes            -= $reallyReadBytes;
			$this->dataReadLength += $reallyReadBytes;

			if ($reallyReadBytes < $toReadBytes)
			{
				// We read less than requested! Why? Did we hit local EOF?
				if ($this->isEOF(true) && !$this->isEOF(false))
				{
					// Yeap. Let's go to the next file
					$this->nextFile();
				}
				else
				{
					// Nope. The archive is corrupt
					debugMsg('Not enough data in file. The archive is truncated or corrupt.');
					$this->setError(AKText::_('ERR_CORRUPT_ARCHIVE'));

					return false;
				}
			}

			if (!$this->mustSkip())
			{
				if (is_resource($outfp))
				{
					@fwrite($outfp, $data);
				}
			}
		}

		// Close the file pointer
		if (!$this->mustSkip())
		{
			if (is_resource($outfp))
			{
				@fclose($outfp);
			}
		}

		// Was this a pre-timeout bail out?
		if ($leftBytes > 0)
		{
			$this->runState = AK_STATE_DATA;
		}
		else
		{
			// Oh! We just finished!
			$this->runState       = AK_STATE_DATAREAD;
			$this->dataReadLength = 0;
		}

		return true;
	}

	private function processTypeFileCompressedSimple()
	{
		if (!$this->mustSkip())
		{
			// Before processing file data, ensure permissions are adequate
			$this->setCorrectPermissions($this->fileHeader->file);

			clearstatcache($this->fileHeader->file);

			// Open the output file
			$outfp = @fopen($this->fileHeader->realFile, 'w');

			// Can we write to the file?
			$ignore =
				AKFactory::get('kickstart.setup.ignoreerrors', false) || $this->isIgnoredDirectory($this->fileHeader->file);

			if ($outfp === false)
			{
				if (!$ignore)
				{
					// An error occurred
					debugMsg('Could not write to output file');
					$this->setError(AKText::sprintf('COULDNT_WRITE_FILE', $this->fileHeader->realFile));

					return false;
				}

				// "Skip most errors" is on: record the skipped file and carry on. The
				// archive data is still consumed below so the stream stays aligned.
				debugMsg('Skipping unwritable output file ' . $this->fileHeader->realFile);
				$this->setWarning(AKText::sprintf('Skipped (could not write): %s', $this->fileHeader->realFile));
			}
		}

		// Does the file have any data, at all?
		if ($this->fileHeader->compressed == 0)
		{
			// No file data!
			if (!$this->mustSkip())
			{
				if (is_resource($outfp))
				{
					@fclose($outfp);
				}
			}
			$this->runState = AK_STATE_DATAREAD;

			return true;
		}

		// Simple compressed files are processed as a whole; we can't do chunk processing
		$zipData = $this->fread($this->fp, $this->fileHeader->compressed);
		while (akstringlen($zipData) < $this->fileHeader->compressed)
		{
			// End of local file before reading all data, but have more archive parts?
			if ($this->isEOF(true) && !$this->isEOF(false))
			{
				// Yeap. Read from the next file
				$this->nextFile();
				$bytes_left = $this->fileHeader->compressed - akstringlen($zipData);
				$zipData    .= $this->fread($this->fp, $bytes_left);
			}
			else
			{
				debugMsg('End of local file before reading all data with no more parts left. The archive is corrupt or truncated.');
				$this->setError(AKText::_('ERR_CORRUPT_ARCHIVE'));

				return false;
			}
		}

		if ($this->fileHeader->compression == 'gzip')
		{
			$unzipData = gzinflate($zipData);
		}
		elseif ($this->fileHeader->compression == 'bzip2')
		{
			$unzipData = bzdecompress($zipData);
		}
		unset($zipData);

		// Write to the file.
		if (!$this->mustSkip() && is_resource($outfp))
		{
			@fwrite($outfp, $unzipData, $this->fileHeader->uncompressed);
			@fclose($outfp);
		}
		unset($unzipData);

		$this->runState = AK_STATE_DATAREAD;

		return true;
	}
}
