@echo off
setlocal

REM ── ARIA Assistant – voice-ready mode (Windows) ─────────────────────────────
REM  Launches the Flutter app and automatically activates the microphone
REM  as soon as the main screen appears.

cd /d "%~dp0..\.."
set ARIA_START_VOICE_READY=true
echo [ARIA] Starting with voice recording auto-activated...
flutter run -d windows
