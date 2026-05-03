@echo off
setlocal

REM ── ARIA Assistant – kiosk mode (Windows) ───────────────────────────────────
REM  Launches the Flutter app full-screen with no window chrome.
REM  Set ARIA_KIOSK=true so the running process reads the flag at start-up.

cd /d "%~dp0..\.."
set ARIA_KIOSK=true
echo [ARIA] Starting in kiosk (full-screen) mode...
flutter run -d windows
