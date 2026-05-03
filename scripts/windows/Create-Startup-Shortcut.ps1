#Requires -Version 5.1
<#
.SYNOPSIS
    Creates a Windows Startup-folder shortcut so ARIA Assistant launches on login.

.DESCRIPTION
    Places a .lnk shortcut in the current user's Startup folder
    (%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup).
    ARIA will then open automatically whenever you sign in to Windows.

.PARAMETER AppPath
    Full path to noa.exe.  Auto-detected from the project layout if omitted.

.PARAMETER Arguments
    Optional launch arguments, e.g. "--kiosk" or "--start-voice-ready".

.EXAMPLE
    .\Create-Startup-Shortcut.ps1
    .\Create-Startup-Shortcut.ps1 -Arguments "--start-voice-ready"

.NOTES
    To remove auto-start, delete the shortcut from:
        %APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\ARIA Assistant.lnk
    Or run:
        Remove-Item "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\ARIA Assistant.lnk"
#>
param(
    [string]$AppPath   = "",
    [string]$Arguments = ""
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
    } elseif (Test-Path $DebugPath) {
        $AppPath = $DebugPath
        Write-Host "[ARIA] Warning: using Debug build for startup shortcut." -ForegroundColor Yellow
    } else {
        Write-Error "No ARIA build found. Run: flutter build windows --release"
        exit 1
    }
}

if (-not (Test-Path $AppPath)) {
    Write-Error "Executable not found: $AppPath"
    exit 1
}

# ── Create the shortcut in the Startup folder ────────────────────────────────
$StartupDir   = [Environment]::GetFolderPath('Startup')
$ShortcutPath = Join-Path $StartupDir "ARIA Assistant.lnk"

$Shell    = New-Object -ComObject WScript.Shell
$Shortcut = $Shell.CreateShortcut($ShortcutPath)

$Shortcut.TargetPath       = $AppPath
$Shortcut.WorkingDirectory = Split-Path $AppPath -Parent
$Shortcut.Description      = "ARIA Voice Assistant – auto-start on login"
if ($Arguments) { $Shortcut.Arguments = $Arguments }
$Shortcut.Save()

Write-Host "[ARIA] Startup shortcut created:" -ForegroundColor Green
Write-Host "       $ShortcutPath"
Write-Host ""
Write-Host "ARIA will now launch automatically on Windows login." -ForegroundColor Cyan
Write-Host "To disable: delete $ShortcutPath"
