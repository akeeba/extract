; ============================================================================
; Akeeba Extract — Windows installer (NSIS)
; A cross-platform desktop application to extract Akeeba Backup archives
;
; Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
; License: GNU General Public License version 3, or later
;
; This NSIS script is the cross-compilable Windows installer: its compiler,
; `makensis`, runs NATIVELY on macOS and Linux (brew install makensis), so the
; installer is produced from the same machine as the rest of the build — no
; Wine, Docker, or Windows host required.
;
;   makensis -DSRCDIR=build/output/windows/amd64 \
;            -DOUTFILE=build/output/Akeeba-Extract-Setup.exe \
;            build/windows-installer.nsi
;
; build/build-all.sh invokes it automatically when `makensis` is on PATH.
;
; Source layout produced by `php vendor/bin/boson compile` (SRCDIR):
;   akeeba-extract.exe            — main application binary
;   libboson-windows-x86_64.dll   — Boson WebView runtime DLL (must sit beside the .exe)
;   public/                       — HTML/CSS/JS UI (must sit beside the .exe; mounted at runtime)
;
; The installer is per-user (no admin needed), matching a "lowest privileges"
; install: it lands in %LOCALAPPDATA%\Programs\Akeeba Extract.
; ============================================================================

Unicode true

; ---- Overridable defines (passed with -D… by build-all.sh) -----------------
; NOTE: makensis changes its working directory to this script's folder, so
; relative paths must be anchored with ${__FILEDIR__} (the build/ directory).
; build-all.sh passes absolute SRCDIR/OUTFILE; these are sensible defaults for
; a direct `makensis build/windows-installer.nsi` invocation.
!ifndef SRCDIR
  !define SRCDIR "${__FILEDIR__}/output/windows/amd64"
!endif
!ifndef OUTFILE
  !define OUTFILE "${__FILEDIR__}/output/Akeeba-Extract-Setup.exe"
!endif
; No default: the version is always supplied by the caller (build-all.sh /
; make-windows-installer.sh / Phing), sourced from src/App.php::VERSION.
!ifndef APPVERSION
  !error "APPVERSION must be defined (pass -DAPPVERSION=<version>)"
!endif
; VIProductVersion requires a strict X.X.X.X numeric form, unlike APPVERSION
; (e.g. "0.1"), so the caller pads/sanitises it separately into VIVERSION.
!ifndef VIVERSION
  !error "VIVERSION must be defined (pass -DVIVERSION=<major.minor.build.revision>)"
!endif
!ifndef LICENSEFILE
  !define LICENSEFILE "${__FILEDIR__}/../LICENSE.txt"
!endif
; Application .ico. makensis chdir's into this script's folder (build/), so the
; bare filename resolves there; build-all.sh passes an absolute path via -D.
!ifndef ICONFILE
  !define ICONFILE "extract.ico"
!endif

!define APPNAME    "Akeeba Extract"
!define PUBLISHER  "Nicholas K. Dionysopoulos / Akeeba Ltd"
!define APPURL     "https://github.com/akeeba/extract"
!define APPEXE     "akeeba-extract.exe"
!define APPPHAR    "akeeba-extract.phar"
!define APPDLL     "libboson-windows-x86_64.dll"
!define APPICON    "extract.ico"
!define REGUNINST  "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}"

; Application icon (sits beside this script in build/). Used for the installer
; and uninstaller chrome, and installed beside the .exe so shortcuts, file
; associations and Add/Remove Programs all show the Akeeba Extract icon.
; (The Boson-compiled .exe carries a generic icon; bundling the .ico and
; pointing shortcuts/associations at it gives the app its real icon.)
!define MUI_ICON   "${ICONFILE}"
!define MUI_UNICON "${ICONFILE}"

; ---- Installer attributes --------------------------------------------------
Name "${APPNAME}"
OutFile "${OUTFILE}"
RequestExecutionLevel user
InstallDir "$LOCALAPPDATA\Programs\${APPNAME}"
InstallDirRegKey HKCU "Software\${APPNAME}" "InstallDir"
SetCompressor /SOLID lzma
VIProductVersion "${VIVERSION}"
VIAddVersionKey "ProductName"     "${APPNAME}"
VIAddVersionKey "FileDescription" "${APPNAME} installer"
VIAddVersionKey "LegalCopyright"  "(c) 2026 ${PUBLISHER}"
VIAddVersionKey "FileVersion"     "${APPVERSION}"
VIAddVersionKey "ProductVersion"  "${APPVERSION}"

; ---- Modern UI -------------------------------------------------------------
!include "MUI2.nsh"
!define MUI_ABORTWARNING

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "${LICENSEFILE}"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_RUN "$INSTDIR\${APPEXE}"
!define MUI_FINISHPAGE_RUN_TEXT "Launch ${APPNAME}"
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"

; ---- Install ---------------------------------------------------------------
Section "Install"
    SetOutPath "$INSTDIR"
    File "${SRCDIR}/${APPEXE}"
    File "${SRCDIR}/${APPDLL}"
    ; Microsoft VC++ runtime, deployed app-local. ${APPDLL} imports these four
    ; and none of them ship with Windows; bundling them means the user never
    ; needs the (admin-only) VC++ redistributable installer. HAVE_VCREDIST is
    ; passed by make-windows-installer.sh only when build/redist/win-x64/ was
    ; populated (build/fetch-vcredist.sh).
!ifdef HAVE_VCREDIST
    File "${SRCDIR}/msvcp140.dll"
    File "${SRCDIR}/msvcp140_atomic_wait.dll"
    File "${SRCDIR}/vcruntime140.dll"
    File "${SRCDIR}/vcruntime140_1.dll"
!endif
    File "/oname=${APPICON}" "${ICONFILE}"

    ; A code-signed build ships the app payload as a sibling PHAR beside the
    ; signed stub (akeeba-extract.exe), rather than appended to it — Authenticode
    ; would corrupt an appended PHAR's trailing signature. The patched phpmicro
    ; stub loads "akeeba-extract.phar" from its own directory at run time.
    ; HAVE_PHAR is passed by build/make-windows-installer.sh only when it split
    ; the binary.
!ifdef HAVE_PHAR
    File "${SRCDIR}/${APPPHAR}"
!endif

    ; The UI assets must sit next to the executable (the runtime mounts public/
    ; relative to the binary; without it the app shows a 404).
    SetOutPath "$INSTDIR\public"
    File /r "${SRCDIR}/public/*.*"

    ; The language catalogues are mounted the same way; without them the engine
    ; and UI fall back to raw language keys.
    SetOutPath "$INSTDIR\language"
    File /r "${SRCDIR}/language/*.*"

    ; Shortcuts
    SetOutPath "$INSTDIR"
    CreateDirectory "$SMPROGRAMS\${APPNAME}"
    CreateShortCut "$SMPROGRAMS\${APPNAME}\${APPNAME}.lnk" "$INSTDIR\${APPEXE}" "" "$INSTDIR\${APPICON}" 0
    CreateShortCut "$SMPROGRAMS\${APPNAME}\Uninstall ${APPNAME}.lnk" "$INSTDIR\uninstall.exe"

    ; File associations (.jpa / .jps), per-user
    WriteRegStr HKCU "Software\Classes\.jpa" "" "AkeebaExtract.Archive"
    WriteRegStr HKCU "Software\Classes\.jps" "" "AkeebaExtract.Archive"
    WriteRegStr HKCU "Software\Classes\AkeebaExtract.Archive" "" "Akeeba Backup Archive"
    WriteRegStr HKCU "Software\Classes\AkeebaExtract.Archive\DefaultIcon" "" "$INSTDIR\${APPICON},0"
    WriteRegStr HKCU "Software\Classes\AkeebaExtract.Archive\shell\open\command" "" '"$INSTDIR\${APPEXE}" "%1"'

    ; Remember install dir + register uninstaller in Add/Remove Programs
    WriteRegStr HKCU "Software\${APPNAME}" "InstallDir" "$INSTDIR"
    WriteRegStr HKCU "${REGUNINST}" "DisplayName"     "${APPNAME}"
    WriteRegStr HKCU "${REGUNINST}" "DisplayVersion"  "${APPVERSION}"
    WriteRegStr HKCU "${REGUNINST}" "Publisher"       "${PUBLISHER}"
    WriteRegStr HKCU "${REGUNINST}" "URLInfoAbout"    "${APPURL}"
    WriteRegStr HKCU "${REGUNINST}" "DisplayIcon"     "$INSTDIR\${APPICON}"
    WriteRegStr HKCU "${REGUNINST}" "UninstallString" "$INSTDIR\uninstall.exe"
    WriteRegDWORD HKCU "${REGUNINST}" "NoModify" 1
    WriteRegDWORD HKCU "${REGUNINST}" "NoRepair" 1

    WriteUninstaller "$INSTDIR\uninstall.exe"
SectionEnd

; ---- Uninstall -------------------------------------------------------------
Section "Uninstall"
    Delete "$INSTDIR\${APPEXE}"
    Delete "$INSTDIR\${APPPHAR}"
    Delete "$INSTDIR\${APPDLL}"
    ; App-local VC++ runtime (unconditional: harmless if never installed, and
    ; this way an uninstall still cleans up after an older bundled build).
    Delete "$INSTDIR\msvcp140.dll"
    Delete "$INSTDIR\msvcp140_atomic_wait.dll"
    Delete "$INSTDIR\vcruntime140.dll"
    Delete "$INSTDIR\vcruntime140_1.dll"
    Delete "$INSTDIR\${APPICON}"
    RMDir /r "$INSTDIR\public"
    RMDir /r "$INSTDIR\language"
    Delete "$INSTDIR\uninstall.exe"
    RMDir "$INSTDIR"

    Delete "$SMPROGRAMS\${APPNAME}\${APPNAME}.lnk"
    Delete "$SMPROGRAMS\${APPNAME}\Uninstall ${APPNAME}.lnk"
    RMDir "$SMPROGRAMS\${APPNAME}"

    DeleteRegKey HKCU "Software\Classes\.jpa"
    DeleteRegKey HKCU "Software\Classes\.jps"
    DeleteRegKey HKCU "Software\Classes\AkeebaExtract.Archive"
    DeleteRegKey HKCU "Software\${APPNAME}"
    DeleteRegKey HKCU "${REGUNINST}"
SectionEnd
