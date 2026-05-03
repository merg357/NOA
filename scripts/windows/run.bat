@echo off
setlocal

REM ── ARIA Assistant – development run (Windows) ──────────────────────────────
REM  Launches the Flutter app in debug mode on the Windows desktop target.
REM  Requires Flutter SDK in PATH. Run from the project root or any subdirectory.

cd /d "%~dp0..\.."
echo [ARIA] Starting in development mode...
flutter run -d windows
