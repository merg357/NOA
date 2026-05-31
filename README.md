# Noa + ARIA for iOS and Android – A Flutter app for Frame

Welcome to the Noa app repository! Built using Flutter, this repository also serves as a great example of how to build your own Frame apps.

> **Note**: This fork extends the original Noa app with ARIA — a productivity-first wearable assistant layer for Brilliant Labs Frame. See the [ARIA feature summary](#aria-feature-summary) below.

<p style="text-align: center;"><a href="https://apps.apple.com/us/app/noa-for-frame/id6482980023"><img src="https://upload.wikimedia.org/wikipedia/commons/3/3c/Download_on_the_App_Store_Badge.svg" alt="Apple App Store badge" width="125"/></a>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href="https://play.google.com/store/apps/details?id=xyz.brilliant.noaflutter"><img src="https://upload.wikimedia.org/wikipedia/commons/7/78/Google_Play_Store_badge_EN.svg" alt="Google Play Store badge" width="125"/></a></p>

![Noa screenshots](/docs/screenshots.png)

## ARIA Feature Summary

### Live pages (reachable from the app)

| Tab | Page | Status |
|-----|------|--------|
| CHAT (0) | `NoaPage` | ✅ Live — voice via Frame tap + text command input bar + **Interpreter Panel** |
| LENS (1) | `VisionPage` | ✅ Live — camera/gallery capture; pluggable `VisionAnalysisProvider` |
| TASKS (2) | `ProductivityPage` | ✅ Live — reminders, notes, memory facts; SharedPreferences backed |
| TUNE (3) | `TunePage` | ✅ Live — existing Noa settings + "ARIA Settings →" link |
| TUNE → | `AriaSettingsPage` | ✅ Live — persona, mode, Gemini Live, **Interpreter Mode**, **Earbud Mode**, VPS |
| LOG (4) | `HackPage` | ✅ Live — BLE + app log viewer |

---

## Interpreter Mode

Interpreter Mode turns the Gemini Live voice session into a real-time spoken language interpreter. It is a specialization of the existing Gemini Live path — no separate backend is needed.

### How it works

When Interpreter Mode is enabled, the Gemini Live session receives a strict system instruction that replaces the normal ARIA assistant persona. Gemini is told to:

1. Detect or accept the source language.
2. Translate naturally into the target language.
3. Respond in a fixed parseable template:

```
SOURCE_LANGUAGE: Spanish
ORIGINAL: ¿Cómo estás?
TRANSLATION: How are you?
PRONUNCIATION: 
NOTE: Informal greeting
```

The Flutter app parses this template into an `InterpreterResult` object and displays it in the **Interpreter Panel** — a compact widget that appears between the voice banner and the input bar on the Chat screen.

### Modes

| Mode | Behaviour |
|------|-----------|
| **Any → English** | Speak in any language. Gemini auto-detects and translates to English. |
| **English → Target** | Speak English. Gemini translates to the selected target language. |
| **Bidirectional** | Speak either language. Gemini detects and translates in the opposite direction. |

### Supported target languages

Arabic, French, German, Hindi, Italian, Japanese, Korean, Mandarin, Portuguese, Russian, Spanish, Turkish.

### Panel actions

- **Swap** — toggle between Any→English and English→Target
- **Copy** — copies the translation text to the clipboard
- **Speak** — sends a re-speak request to the active Gemini Live session
- **Clear** — clears the current result

### How to enable

1. Open **Settings → Interpreter Mode**.
2. Toggle **Enable Interpreter Mode** ON.
3. Select a direction and (if applicable) a target language.
4. Ensure **Gemini Live** is also enabled (Settings → Gemini Live).
5. Return to the **CHAT** tab and tap the mic button.

### Frame integration

Interpreter results produce compact wearable cards sent to Frame (if connected):
```
[source language] → EN
[short translation]
[pronunciation line]
```
Frame hardware is **not required** for interpreter mode to function.

---

## Earbud Mode

Earbud Mode routes Android communication audio to a Bluetooth headset/earbuds when available.

### How it works

- A native Android `AudioRoutePlugin` (Kotlin) exposes a `MethodChannel` at `noa/audio_route`.
- On Android API 31+ it calls `AudioManager.setCommunicationDevice()` to prefer the Bluetooth device.
- On older Android or non-Android platforms, all operations are no-ops and the app falls back cleanly to the phone microphone/speaker.
- The Flutter `AudioRouteService` wraps the channel with graceful error handling.

### Testing with Bluetooth earbuds

1. Pair your Bluetooth earbuds with the phone.
2. Open **Settings → Earbud Mode** and enable **Enable Earbud Mode**.
3. Tap **Refresh devices** — your earbuds should appear in the device list.
4. The "Active route" row shows the selected device.
5. Start a Gemini Live or Interpreter session — audio should route to the earbuds.

### What still requires a real Android device

- Actual Bluetooth audio routing (`AudioManager.setCommunicationDevice`) — this cannot be emulated on desktop or iOS.
- The device list will be empty on non-Android platforms.

### What still requires Brilliant Frame hardware

- BLE pairing, tap-to-capture photo, BLE audio streaming.
- Wearable card display on Frame.
- Interpreter mode itself works without Frame hardware.

---

### Text command routing (CHAT bar)

Type commands in the input bar at the bottom of the CHAT screen. Supported patterns:

```
remind me to <text>         → saves a reminder
show my reminders           → lists pending reminders
save note: <text>           → saves a note
show notes                  → lists notes
remember that <text>        → saves a memory fact
recall <query>              → searches memory facts
daily brief                 → generates a summary of pending items
switch to productivity mode → changes assistant mode
switch to focus mode        → changes assistant mode
switch to vision mode       → changes assistant mode
```

Unmatched input shows "Use Frame tap for voice queries" — the Frame tap voice flow is unchanged.

### Real provider backends (wired in session 6)

| Feature | File | Implementation |
|---------|------|---------------|
| STT — OpenAI Whisper | `lib/services/stt_provider.dart` | `OpenAiSttProvider` — multipart POST to `/v1/audio/transcriptions`; falls back to `null` on missing key or network error |
| TTS — OpenAI TTS-1 | `lib/services/tts_provider.dart` | `OpenAiTtsProvider` — POST to `/v1/audio/speech`; saves MP3 to temp dir; falls back to `null` on missing key |
| Assistant — OpenAI Chat | `lib/services/assistant_provider.dart` | `OpenAiAssistantProvider` — POST to `/v1/chat/completions`; includes session history (up to 6 turns), AppMode system prompt, vision capture context; falls back to `MockAssistantProvider` on error |

### Still mock / stub only

| Feature | File | Status |
|---------|------|--------|
| Vision analysis backend | `lib/services/vision_analysis_provider.dart` | Interface wired; default is `MockVisionProvider` — implement `VisionAnalysisProvider` and inject into `VisionService` for real ML/OCR |
| Frame display output | `lib/services/frame_output_service.dart` | Wired in AppLogicModel; reachable via `sendWearableCardToFrame` and VisionPage SEND button |

---

## Voice loop (push-to-talk)

**Session 5** added a full phone-side voice conversation layer.  
Architecture: **mic → STT → session → command router → TTS → phone speaker → Frame card**

### How it works

1. User taps the **mic button** in the CHAT bar → `VoiceController` starts recording 16 kHz mono WAV.
2. Tap again to stop → audio path goes to `SttProvider.transcribeAudioFile`.
3. Transcript is stored in `ConversationSessionService` and forwarded to `CommandRouter`.
4. If the router matches a skill → skill result card sent to Frame + shown in chat.
5. If no match → `_buildMockResponse` generates a mode-aware reply, which appears in chat.
6. `TtsProvider.synthesizeToFile` produces audio → `AudioPlaybackService` plays it.
7. A `WearableCard` with the reply is displayed on the Frame.

### New packages

| Package | Purpose |
|---------|---------|
| `record: ^5.0.4` | Microphone capture (16 kHz mono WAV) |

(`just_audio` was already present and is now wrapped in `AudioPlaybackService`.)

### Permissions

Android — already in `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
```

iOS — already in `Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>ARIA uses your microphone for push-to-talk voice input to the assistant</string>
```

### Voice configuration (`.env.template`)

| Key | Default | Description |
|-----|---------|-------------|
| `OPENAI_API_KEY` | _(empty)_ | Required for all OpenAI backends (STT, TTS, assistant) |
| `ENABLE_STT` | `true` | Show mic button in CHAT bar |
| `ENABLE_TTS` | `false` | Play audio after assistant reply |
| `STT_PROVIDER` | `mock` | `mock` or `openai` (Whisper) |
| `TTS_PROVIDER` | `mock` | `mock` (silent) or `openai` (TTS-1) |
| `TTS_VOICE` | `onyx` | OpenAI TTS voice — alloy, echo, fable, onyx, nova, shimmer |
| `ASSISTANT_PROVIDER` | `mock` | `mock` (canned) or `openai` (Chat Completions) |
| `OPENAI_ASSISTANT_MODEL` | `gpt-4o-mini` | Model name when `ASSISTANT_PROVIDER=openai` |
| `ASSISTANT_PERSONA` | `calm_executive` | Persona style label (informational) |
| `VOICE_MOCK_MODE` | `true` | Forces all providers to mock even when keys are present |

These can also be toggled at runtime via **ARIA Settings → Voice Settings**.

### Mock mode

With `mockMode: true` (the default), no API keys are required:
- STT returns canned phrases from a rotating list.
- TTS is silent (no audio file generated).
- Assistant returns mode-aware canned replies.
- The full voice loop state machine still runs so UI states are visible.

### To activate real providers

1. Copy `.env.template` to `.env`.
2. Set `OPENAI_API_KEY=sk-...` (your OpenAI API key).
3. Set `VOICE_MOCK_MODE=false`.
4. Set the providers you want:
   ```env
   STT_PROVIDER=openai          # Whisper transcription
   TTS_PROVIDER=openai          # TTS-1 speech synthesis
   ASSISTANT_PROVIDER=openai    # GPT-4o-mini chat completions
   OPENAI_ASSISTANT_MODEL=gpt-4o-mini
   ```
5. Run: `flutter run --debug`

Fallback guarantee: if `OPENAI_API_KEY` is empty or a request fails, the app falls back to the mock provider silently — it never crashes on missing credentials.

### Vision providers

`VisionService` accepts any `VisionAnalysisProvider` implementation:

```dart
abstract class VisionAnalysisProvider {
  String get name;                               // shown in logs
  Future<CaptureResult> analyze(String imagePath);
}
```

To add a real backend, create a class that implements `VisionAnalysisProvider` and pass it to `VisionService` in `lib/models/vision_model.dart`:

```dart
final visionProvider = ChangeNotifierProvider<VisionService>(
  (ref) => VisionService(analysisProvider: MyRealVisionProvider()),
);
```

The `MockVisionProvider` (returns a placeholder scene summary after 800 ms) remains the default so the app works without any API credentials.

### Known limitations

- Vision page requires a real device (camera) or an AVD with a virtual camera.
- The ARIA settings page does not have a back button in the bottom nav — use the top-right account/close icon to return.

---

## Getting started

1. Ensure you have XCode and/or Android studio correctly set up for app development

1. Install [Flutter](https://docs.flutter.dev/get-started/install) for VSCode

1. Clone this repository

    ```sh
    git clone https://github.com/brilliantlabsAR/noa-flutter.git
    cd noa-flutter
    ```

1. Get the required packages

    ```sh
    flutter pub get
    ```

1. Create a `.env` file at the project root (can be empty for local dev, populate with Google OAuth IDs for production):

    ```sh
    touch .env
    ```

1. Connect your phone and run the app

    ```sh
    # Android
    flutter run --release

    # iOS (requires macOS + Xcode)
    flutter run --release -d <your-device-id>
    ```

### Running on Android

```sh
# Debug build (no real device needed for productivity/settings features)
flutter build apk --debug

# Install on connected device
flutter install
```

Permissions required (already in `AndroidManifest.xml`): `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`, `CAMERA`, `RECORD_AUDIO`, `READ_MEDIA_IMAGES`.

### Running on iOS

```sh
# Requires a real device or Simulator with camera access
open ios/Runner.xcworkspace   # set Team in Signing & Capabilities
flutter run
```

Privacy descriptions (already in `Info.plist`): `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, `NSPhotoLibraryUsageDescription`, `NSBluetoothAlwaysUsageDescription`.

---

## PC testing mode (Windows desktop launcher)

Run and test ARIA on your Windows PC without a phone or Frame device.  
The desktop build opens directly to the CHAT screen with the mic button, text input, voice state banner, and full nav bar — exactly as on mobile.

### What works on Windows

| Feature | Status |
|---------|--------|
| Chat screen (ARIA messages) | ✅ |
| Push-to-talk mic (record package) | ✅ |
| STT — OpenAI Whisper | ✅ (real or mock) |
| Assistant — OpenAI Chat | ✅ (real or mock) |
| TTS — OpenAI TTS-1 | ✅ (real or mock, just_audio plays MP3) |
| Text command input | ✅ |
| Mode switching (productivity / focus / …) | ✅ |
| TASKS / TUNE / LOG tabs | ✅ |
| Voice settings (mock mode toggle etc.) | ✅ |
| Window size + position saved on close | ✅ |
| Always-on-top toggle (TUNE → SETTINGS) | ✅ |
| Borderless / compact window | ✅ |
| Kiosk (full-screen) mode | ✅ via flag |
| Frame BLE output | ❌ (no-op; BLE not available on PC) |
| Login / account | ❌ (bypassed; app goes straight to CHAT) |
| Vision tab (camera / gallery) | ⚠️ image_picker works on Windows |

### Quick start

```sh
# 1. Get packages (includes window_manager)
flutter pub get

# 2. Run the development build on Windows
flutter run -d windows
# OR use the helper batch file:
scripts\windows\run.bat
```

You will see an "ARIA ASSISTANT" splash screen for 800 ms, then the CHAT screen opens. The window starts at 420 × 720 px (phone proportions) and remembers its last size and position.

### Activate real OpenAI providers

Copy `.env.template` → `.env` and set:

```env
OPENAI_API_KEY=sk-...
VOICE_MOCK_MODE=false
STT_PROVIDER=openai
ASSISTANT_PROVIDER=openai
TTS_PROVIDER=openai          # optional — silent by default
```

Then restart `flutter run -d windows`. All three backends are live; mock fallback is still active if a request fails.

### Build a release executable

```sh
flutter build windows --release
# Executable: build\windows\x64\runner\Release\noa.exe
```

### Create a Desktop shortcut

```powershell
# After flutter build windows --release:
.\scripts\windows\Create-Shortcut.ps1

# Kiosk-mode shortcut (full-screen, no chrome):
.\scripts\windows\Create-Shortcut.ps1 -ShortcutName "ARIA Kiosk" -Arguments "--kiosk"
```

### Enable launch-on-Windows-login

```powershell
.\scripts\windows\Create-Startup-Shortcut.ps1

# With auto-mic activation:
.\scripts\windows\Create-Startup-Shortcut.ps1 -Arguments "--start-voice-ready"

# To disable auto-start later:
Remove-Item "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\ARIA Assistant.lnk"
```

### Launch flags

Set any flag as an OS environment variable **before** launching the EXE (the `.env` file is also respected):

| Flag | Env var | `.env` key | Effect |
|------|---------|-----------|--------|
| `--kiosk` | `ARIA_KIOSK=true` | `DESKTOP_KIOSK=true` | Full-screen, no window chrome |
| `--auto-connect` | `ARIA_AUTO_CONNECT=true` | `DESKTOP_AUTO_CONNECT=true` | Reserved for future BLE |
| `--start-voice-ready` | `ARIA_START_VOICE_READY=true` | `DESKTOP_START_VOICE_READY=true` | Auto-activates mic on launch |

Example — run the built EXE in kiosk mode:

```bat
set ARIA_KIOSK=true
build\windows\x64\runner\Release\noa.exe
```

### Desktop-only settings (TUNE → SETTINGS)

On Windows, the SETTINGS page shows an extra **Desktop Window** section:

- **Always on top** — keeps the ARIA window in front of other apps
- **Borderless / compact mode** — hides the title bar for a minimal look

Both settings are saved to `SharedPreferences` and restored automatically on the next launch.

---

## Gemini Live (real-time voice)

Gemini Live replaces the chained STT → assistant → TTS path with a **stateful WebSocket session**.  
One mic tap opens the session; another tap (or a network close) ends it.  
The session retains conversational context across turns until you stop it.

### How it works

```
mic (16-bit PCM 16 kHz mono)
   │ base64 chunks via WebSocket
   ▼
Gemini Live API  ────────────────────────────────────────────────────────────
   │ audio/pcm;rate=24000 (24 kHz mono 16-bit, base64)
   │ inputTranscription  → ConversationSessionService (user turns)
   │ outputTranscription → ConversationSessionService (model turns) + chat
   ▼
AudioPlaybackService (WAV wrapper over PCM buffer, just_audio)
   │
   ▼
Frame side-channel: status banners + compact WearableCard per turn
```

### Quick setup

1. Get a **Google AI Studio** API key at <https://aistudio.google.com/apikey>.

2. Add to `.env`:

   ```env
   GEMINI_API_KEY=AIza...
   GEMINI_LIVE_ENABLED=true
   ```

3. Run the app:

   ```sh
   flutter run -d windows      # Windows
   flutter run -d <device-id>  # Android / iOS
   ```

4. Tap the mic button in the CHAT tab — the button changes to a WiFi icon while  
   connecting, then a red Stop icon once the session is live.

5. Tap again to end the session cleanly.

### Configuration reference (`.env` / SETTINGS)

| `.env` key | Default | Description |
|-----------|---------|-------------|
| `GEMINI_LIVE_ENABLED` | `false` | Enable Gemini Live as the primary voice path |
| `GEMINI_API_KEY` | — | Google AI Studio key (never commit this) |
| `GEMINI_LIVE_MODEL` | `models/gemini-2.0-flash-live-001` | Gemini Live model |
| `GEMINI_LIVE_VOICE` | `Puck` | Pre-built voice (Puck · Aoede · Charon · Fenrir · Kore) |
| `GEMINI_LIVE_EPHEMERAL_TOKEN_URL` | — | Server URL for production ephemeral tokens |

The **enabled** toggle and current model / voice are also visible in  
**TUNE → SETTINGS → Gemini Live**.

### appMode integration

The current `AppMode` (standard / productivity / vision / meeting / focus) is  
automatically appended to the system instruction before each session, so the  
live conversation adapts to whichever mode you have selected.  
Switch mode in settings and then start a new session to apply the change.

### Production: ephemeral tokens

> ⚠ Never ship your `GEMINI_API_KEY` in a production app binary.

Set up a lightweight server that calls the Google token-vending endpoint and  
returns `{"token":"<short-lived-token>"}`.  Then configure:

```env
GEMINI_LIVE_EPHEMERAL_TOKEN_URL=https://your-server/gemini-token
GEMINI_API_KEY=   # leave blank — the server uses its own key
```

The app will POST to this URL before each session and use the returned token  
for the WebSocket connection.

### Fallback mode

When Gemini Live is **disabled** (default), the app uses the original chained  
path:  
`push-to-talk mic → Whisper STT → assistant (mock or OpenAI) → TTS`.  
All STT / TTS / assistant settings in SETTINGS still control this fallback path.

### Known limitations (May 2025)

| Limitation | Notes |
|-----------|-------|
| Audio only response modality | Gemini Live supports one modality per session; we use AUDIO |
| PCM playback latency | Audio is played after each full turn, not streamed sample-by-sample |
| No mid-session system-prompt change | Stop and restart the session to change appMode during a conversation |
| Ephemeral-token server not included | You must host your own token-vending endpoint for production |
| iOS mic permission required | Declare `NSMicrophoneUsageDescription` in `Info.plist` (already present) |

---

### Running tests

```sh
# All unit tests (voice loop + session + router + wearable cards)
flutter test
```

Key test files:

| File | Tests |
|------|-------|
| `test/conversation_session_test.dart` | Session turn CRUD, cap, context summary |
| `test/voice_loop_test.dart` | Mock STT/TTS, VoiceLoopState, VoiceConfig helpers |



## Regenerating the platform files

Sometimes it may be necessary to regenerate the platform files. To do this, delete the `ios` and `android` folders, and run the following commands. Adjust for your own organization identifier accordingly:

1. Delete the `ios` and `android` folders

    ```sh
    rm -rf android ios
    ```

1. Regenerate them

    ```sh
    flutter create --platforms ios --org xyz.brilliant --project-name noa .
    flutter create --platforms android --org xyz.brilliant --project-name noa .
    ```

1. Regenerate the app icons

    ```sh
    flutter pub run flutter_launcher_icons
    ```
    
1. Insert the following into `ios/Runner/Info.plist` to enable Bluetooth for iOS

    ```
    <dict>
        <key>NSBluetoothAlwaysUsageDescription</key>
        <string>This app always needs Bluetooth to function</string>
        <key>NSBluetoothPeripheralUsageDescription</key>
        <string>This app needs Bluetooth Peripheral to function</string>
        <key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
        <string>This app always needs location and when in use to function</string>
        <key>NSLocationAlwaysUsageDescription</key>
        <string>This app always needs location to function</string>
        <key>NSLocationWhenInUseUsageDescription</key>
        <string>This app needs location when in use to function</string>
        <key>UIBackgroundModes</key>
        <array>
            <string>bluetooth-central</string>
        </array>
        ...
    ```

1. Insert the following into `ios/Runner/Info.plist to enable Google sign in for iOS

    ```
    <dict>
        <key>CFBundleURLTypes</key>
        <array>
            <dict>
                <key>CFBundleTypeRole</key>
                <string>Editor</string>
                <key>CFBundleURLSchemes</key>
                <array>
                    <string>com.googleusercontent.apps.178409912024-a779l8d62k0r94f8qg63bcs77j986htk</string>
                </array>
            </dict>
        </array>
        ...
    ```

    1. Finally, you may want to find and replace all occurrences of the string `xyz.brilliant` to your own reverse-domain bundle identifier

---

## Jarvis VPS System

This fork adds a **VPS-first always-on brain** layer to the app.

### Architecture

```
┌──────────────────────────────┐      BLE
│  Android / Flutter App        │◄─────────────► Brilliant Labs Frame
│  (noa package)               │                (Lua HUD cards)
│  • Gemini Live voice (primary)│
│  • STT → assistant → TTS     │      WebSocket
│  • VpsService (auto-connect)  │◄─────────────► Jarvis VPS (port 8765)
└──────────────────────────────┘                  │
                                                  ├─ FastAPI REST + WS
                                                  ├─ Hermes agent (autonomy)
                                                  ├─ Gemini ephemeral tokens
                                                  └─ Card push → Frame
```

### VPS setup (Linux)

```bash
cd /root/jarvis
cp .env.template .env
# Fill in VPS_BEARER_TOKEN, GEMINI_API_KEY, etc.
bash vps/install.sh          # creates venv, installs systemd service
systemctl status jarvis-vps  # confirm running
```

### VPS environment variables (`.env`)

| Key | Default | Description |
|-----|---------|-------------|
| `VPS_BEARER_TOKEN` | _(empty = dev mode)_ | Secret shared with mobile app |
| `VPS_HOST` | `0.0.0.0` | Bind address |
| `VPS_PORT` | `8765` | Listen port |
| `VPS_LOG_LEVEL` | `info` | uvicorn log level |
| `GEMINI_API_KEY` | _(empty)_ | Google AI Studio key for Gemini Live ephemeral tokens |
| `GEMINI_LIVE_MODEL` | `gemini-2.0-flash-live-001` | Model name |
| `HERMES_STATE_DB` | `/root/.hermes/state.db` | Hermes SQLite state database |
| `ENABLE_HERMES` | `true` | Enable Hermes agent integration |

### Mobile app VPS config

In `.env` or **ARIA Settings → VPS**:

| Key | Default | Description |
|-----|---------|-------------|
| `VPS_BASE_URL` | `http://localhost:8765` | VPS REST base URL |
| `VPS_WS_URL` | `ws://localhost:8765/ws` | VPS WebSocket URL |
| `VPS_BEARER_TOKEN` | _(empty)_ | Must match server token |
| `VPS_DEVICE_ID` | _(auto UUID)_ | Per-device identifier |
| `GEMINI_LIVE_EPHEMERAL_TOKEN_URL` | _(empty)_ | Point to `http://VPS_HOST:8765/gemini/ephemeral-token` |

### VPS backend tests

```bash
cd /root/jarvis
vps/.venv/bin/pytest vps/tests/ -v
```

16 tests covering health, auth, Hermes trigger, card push, WebSocket protocol.

### Design workflow

See [DESIGN_WORKFLOW.md](DESIGN_WORKFLOW.md) for the open-design integration guide
covering app screens, Frame HUD cards, admin dashboard, and landing page.
