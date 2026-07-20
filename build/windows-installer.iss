; ============================================================================
; Akeeba Extract — Windows Installer (Inno Setup 6.x)
; A cross-platform desktop application to extract Akeeba Backup archives
;
; Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
; License: GNU General Public License version 3, or later
;
; Build instructions (run on Windows):
;   1. Install Inno Setup 6: https://jrsoftware.org/isinfo.php
;   2. Run `php vendor/bin/boson compile` to produce build/output/windows/amd64/*.
;   3. Open this .iss file in the Inno Setup IDE, or from the command line:
;      "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" build\windows-installer.iss
;   4. The installer appears at: build\output\Akeeba-Extract-Setup.exe
;
; The compiler emits these files into build/output/windows/amd64/:
;   akeeba-extract.exe           — the main application binary
;   libboson-windows-x86_64.dll  — Boson WebView runtime DLL
; ============================================================================

#define AppName      "Akeeba Extract"
; No default: the version is always supplied by the caller (build-all.sh /
; make-windows-installer.sh), sourced from src/App.php::VERSION, via /DAppVersion=...
#ifndef AppVersion
  #error AppVersion must be defined (pass /DAppVersion=<version> to ISCC)
#endif
#define AppPublisher "Nicholas K. Dionysopoulos / Akeeba Ltd"
#define AppURL       "https://github.com/akeeba/extract"
#define AppExeName   "akeeba-extract.exe"
#define AppPharName  "akeeba-extract.phar"
#define AppDllName   "libboson-windows-x86_64.dll"
#define AppIcon      "extract.ico"
; Source directory for the compiled binaries. make-windows-installer.sh overrides
; this with /DBinDir=<split staging dir> for a code-signed build, where the app
; payload ships as a sibling akeeba-extract.phar beside the signed stub rather
; than appended to it (Authenticode would corrupt an appended PHAR's trailer).
#ifndef BinDir
  #define BinDir     "..\build\output\windows\amd64"
#endif

[Setup]
; ---- Identity ----
AppId={{A3B1C2D4-E5F6-7890-ABCD-EF1234567890}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
AppUpdatesURL={#AppURL}

; ---- Output ----
OutputDir=..\build\output
OutputBaseFilename=Akeeba-Extract-Setup
; Installer/uninstaller chrome icon (this .iss lives in build/, beside the .ico)
SetupIconFile={#AppIcon}

; ---- Install locations ----
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes

; ---- Compression ----
Compression=lzma2/ultra64
SolidCompression=yes
LZMAUseSeparateProcess=yes

; ---- UI ----
WizardStyle=modern
WizardSizePercent=100

; ---- Target ----
; Requires 64-bit Windows (the Boson runtime is x86_64 only)
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763

; ---- Misc ----
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppIcon}
ChangesAssociations=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon";    Description: "Create a &desktop shortcut";    GroupDescription: "Additional shortcuts:"
Name: "startupicon";   Description: "Launch automatically at &startup"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
; Main binary
Source: "{#BinDir}\{#AppExeName}"; DestDir: "{app}"; Flags: ignoreversion
; Sibling PHAR payload for a code-signed (split) build — the patched phpmicro
; stub loads it from its own directory at run time. HavePhar is passed by
; make-windows-installer.sh only when it split the binary.
#ifdef HavePhar
Source: "{#BinDir}\{#AppPharName}"; DestDir: "{app}"; Flags: ignoreversion
#endif
; Boson WebView runtime DLL — must be beside the .exe
Source: "{#BinDir}\{#AppDllName}"; DestDir: "{app}"; Flags: ignoreversion
; Microsoft VC++ runtime, deployed app-local. The Boson DLL imports these four
; and none ship with Windows, so bundling them avoids sending users to the
; admin-only VC++ redistributable installer. HaveVCRedist is passed by
; make-windows-installer.sh only when build/redist/win-x64/ was populated
; (build/fetch-vcredist.sh).
#ifdef HaveVCRedist
Source: "{#BinDir}\msvcp140.dll";              DestDir: "{app}"; Flags: ignoreversion
Source: "{#BinDir}\msvcp140_atomic_wait.dll";  DestDir: "{app}"; Flags: ignoreversion
Source: "{#BinDir}\vcruntime140.dll";          DestDir: "{app}"; Flags: ignoreversion
Source: "{#BinDir}\vcruntime140_1.dll";        DestDir: "{app}"; Flags: ignoreversion
#endif
; UI assets — the runtime mounts public/ relative to the binary; without it the
; app shows a 404. Must sit next to the .exe.
Source: "{#BinDir}\public\*"; DestDir: "{app}\public"; Flags: ignoreversion recursesubdirs createallsubdirs
; Language catalogues — mounted the same way; without them the engine and UI
; fall back to raw language keys.
Source: "{#BinDir}\language\*"; DestDir: "{app}\language"; Flags: ignoreversion recursesubdirs createallsubdirs
; Application icon — installed so shortcuts and file associations can show it
; (the Boson-compiled .exe carries a generic icon).
Source: "{#AppIcon}"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#AppName}";              Filename: "{app}\{#AppExeName}"; IconFilename: "{app}\{#AppIcon}"
Name: "{group}\Uninstall {#AppName}";    Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}";        Filename: "{app}\{#AppExeName}"; IconFilename: "{app}\{#AppIcon}"; Tasks: desktopicon
Name: "{userstartup}\{#AppName}";        Filename: "{app}\{#AppExeName}"; Tasks: startupicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent

[Registry]
; Associate .jpa files with Akeeba Extract
Root: HKCU; Subkey: "Software\Classes\.jpa";               ValueType: string; ValueName: ""; ValueData: "AkeebaExtract.Archive"; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\AkeebaExtract.Archive"; ValueType: string; ValueName: ""; ValueData: "Akeeba Backup Archive"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\AkeebaExtract.Archive\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#AppIcon},0"
Root: HKCU; Subkey: "Software\Classes\AkeebaExtract.Archive\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExeName}"" ""%1"""

; Associate .jps files
Root: HKCU; Subkey: "Software\Classes\.jps";               ValueType: string; ValueName: ""; ValueData: "AkeebaExtract.EncryptedArchive"; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\AkeebaExtract.EncryptedArchive"; ValueType: string; ValueName: ""; ValueData: "Akeeba Encrypted Backup Archive"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\AkeebaExtract.EncryptedArchive\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#AppIcon},0"
Root: HKCU; Subkey: "Software\Classes\AkeebaExtract.EncryptedArchive\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExeName}"" ""%1"""

[Code]
// Optional: warn if WebView2 runtime is not installed (Boson uses OS WebView)
function InitializeSetup(): Boolean;
begin
  Result := True;
  // WebView2 has been included in Windows 10 21H2+ and all Windows 11 builds.
  // If you need to target older Windows 10, prompt the user to install WebView2:
  //   https://developer.microsoft.com/en-us/microsoft-edge/webview2/
end;
