#Requires -Version 5.1
<#
.SYNOPSIS
    Creates a Desktop shortcut for ARIA Assistant (Windows release build).

.DESCRIPTION
    Locates the built ARIA Assistant executable and creates a .lnk shortcut on
    the current user's Desktop.  If the Release build isn't found it falls back
    to the Debug build so you can test immediately after `flutter run`.

.PARAMETER AppPath
    Full path to noa.exe.  Auto-detected from the project layout if omitted.

.PARAMETER ShortcutName
    Display name for the shortcut file.  Defaults to "ARIA Assistant".

.PARAMETER Arguments
    Optional command-line arguments to embed in the shortcut, e.g. "--kiosk".

.EXAMPLE
    .\Create-Shortcut.ps1
    .\Create-Shortcut.ps1 -ShortcutName "ARIA Kiosk" -Arguments "--kiosk"

.NOTES
    Build first: flutter build windows --release
#>
param(
    [string]$AppPath    = "",
    [string]$ShortcutName = "ARIA Assistant",
    [string]$Arguments  = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Locate the executable ────────────────────────────────────────────────────
$ScriptDir   = Split-Path $PSCommandPath -Parent
$ProjectRoot = (Resolve-Path (Join-Path $ScriptDir "..\..\")).Path

if (-not $AppPath) {
    $ReleasePath = Join-Path $ProjectRoot "build\windows\x64\runner\Release\noa.exe"
    $DebugPath   = Join-Path $ProjectRoot "build\windows\x64\runner\Debug\noa.exe"

    if (Test-Path $ReleasePath) {
        $AppPath = $ReleasePath
        Write-Host "[ARIA] Using Release build." -ForegroundColor Cyan
    } elseif (Test-Path $DebugPath) {
        $AppPath = $DebugPath
        Write-Host "[ARIA] Release build not found – using Debug build." -ForegroundColor Yellow
    } else {
        Write-Error @"
No ARIA build found.
Run one of:
  flutter build windows --release    (preferred)
  flutter run -d windows             (debug)
Then run this script again.
"@
        exit 1
    }
}

if (-not (Test-Path $AppPath)) {
    Write-Error "Executable not found: $AppPath"
    exit 1
}

# ── Create the shortcut ──────────────────────────────────────────────────────
$Desktop      = [Environment]::GetFolderPath('Desktop')
$ShortcutPath = Join-Path $Desktop "$ShortcutName.lnk"

$Shell    = New-Object -ComObject WScript.Shell
$Shortcut = $Shell.CreateShortcut($ShortcutPath)

$Shortcut.TargetPath       = $AppPath
$Shortcut.WorkingDirectory = Split-Path $AppPath -Parent
$Shortcut.Description      = "ARIA Voice Assistant for Brilliant Labs Frame"
if ($Arguments) { $Shortcut.Arguments = $Arguments }
$Shortcut.Save()

Write-Host "[ARIA] Desktop shortcut created:" -ForegroundColor Green
Write-Host "       $ShortcutPath"
