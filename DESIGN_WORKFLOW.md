# Design Workflow — Jarvis Assistant System

> **Scope**: This document explains how to use open-design tooling for UI/UX
> work on the Jarvis system. Open-design is **not** a runtime dependency —
> it is used only for design asset creation, prototyping, and design reviews.

---

## 1. Android / Flutter App Screens

### Key screens to design
| Screen | File | Notes |
|--------|------|-------|
| Chat (CHAT) | `lib/pages/noa.dart` | Primary voice/chat screen |
| Vision (LENS) | `lib/pages/vision.dart` | Camera capture + analysis |
| Tasks (TASKS) | `lib/pages/productivity.dart` | Reminders, notes, memory facts |
| Settings | `lib/pages/aria_settings.dart` | VPS config, Gemini Live, voice |
| Log/Debug (LOG) | `lib/pages/hack.dart` | BLE + app log viewer |

### Design specs
- **Color palette**: dark background `#292929`, accent `#B6BEC9`, white `#FFFFFF`, danger `#DC0000`
- **Typography**: system default, heading 18 sp bold, body 15 sp, subtext 12 sp
- **Spacing**: 24 px horizontal padding, 16 px section gap
- **Corner radius**: 8–10 px for cards and input fields
- **Icons**: Unicode glyphs (`⬡ ✓ ◎ ◈ ◆`) — no external icon font required

### open-design workflow
1. Export screen mock-ups as PNG/SVG from your design tool.
2. Reference `lib/style.dart` for exact colors and text styles.
3. Use `assets/images/` for any images added to the app.
4. Prototype interactions in a design tool; implement in Flutter.

---

## 2. Frame HUD Cards (Brilliant Frame)

### Constraints
- Max **200 characters** total per card (enforced by `WearableCard.toFrameString()`)
- Format: `<icon> <title>\n<body>` — single block of text
- Monospace-friendly: avoid complex Unicode outside the Frame glyph set
- Frame display is small — keep body to 1–2 short sentences

### Card types (see `lib/models/wearable_card.dart`)
| Type | `WearableCardType` | Use for |
|------|--------------------|---------|
| Info | `info` | Assistant replies |
| Alert | `alert` | Urgent notifications |
| Reminder | `reminder` | Saved reminders |
| Daily Brief | `dailyBrief` | Morning summaries |
| Vision | `visionSummary` | Camera analysis results |
| Timer | `timer` | Countdown / elapsed |

### Status banners (sent by `FrameOutputService`)
| Banner | When |
|--------|------|
| `Listening…` | Mic is recording |
| `Thinking…` | STT done, assistant processing |
| `Speaking…` | TTS playing |
| `Connecting…` | Gemini Live handshake |
| `Interrupted` | User interrupted model turn |

### Design workflow
1. Sketch HUD layouts at the Frame display resolution (~640×400 px equivalent).
2. Use `WearableCard.toFrameString()` output as the text mock-up.
3. Frame Lua scripts are in `assets/lua_scripts/` — edit `app.lua` for display logic.
4. Test with `AppLogicModel.sendWearableCardToFrame(card)` via the CHAT screen debug.

---

## 3. VPS Ops / Admin Dashboard

The VPS backend exposes a REST + WebSocket API at port 8765.
A future admin dashboard could be a lightweight web page served by the VPS.

### Key endpoints to surface in a dashboard
| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/health` | GET | Service status, connected devices |
| `/hermes/ping` | GET | Hermes agent status |
| `/hermes/trigger` | POST | Trigger a named task |
| `/cards/push` | POST | Push a card to a device |
| `/cards/status` | POST | Push a status banner |
| `/gemini/ephemeral-token` | POST | Vend a Gemini Live token |

### Design workflow
1. Build the dashboard as a separate HTML/JS SPA or a lightweight Flutter web build.
2. Authenticate with the same `VPS_BEARER_TOKEN` (set in VPS `.env`).
3. Use Server-Sent Events or poll `/health` for live status.
4. The dashboard is **not** part of the main Flutter app — keep it separate.

---

## 4. Landing Page / Product Deck

### Purpose
- Explain the Jarvis system to users, investors, or testers.
- Highlight: always-on VPS brain, Gemini Live voice, Frame HUD, Hermes autonomy.

### Key messages
1. **Always listening, never invasive** — VPS stays on 24/7, phone connects on demand.
2. **Wearable-first** — Frame HUD shows compact, actionable cards.
3. **Conversational** — Gemini Live delivers natural, low-latency voice AI.
4. **Autonomous** — Hermes handles scheduling, reminders, daily briefs on the VPS.

### Assets to create
- Hero screenshot: Frame on face + phone chat screen side-by-side
- Architecture diagram: Phone ↔ VPS ↔ Hermes ↔ Gemini
- App icon: `assets/app_icon.png` (already present)
- Brand colors: use the app palette above

### Design workflow
1. Use any design tool (Figma, Canva, etc.) for landing page mock-ups.
2. Implement as a static site (Netlify / Vercel) or add a `/web` route to the VPS.
3. Reference `assets/images/` for logo and tutorial images.

---

## 5. How open-design integrates

open-design is a **prompt-driven design workflow tool** — not a runtime library.

### Usage pattern
```bash
# Generate a screen spec from a prompt
open-design generate --prompt "Settings screen for VPS config with dark theme"

# Export assets
open-design export --format png --out assets/images/

# Review design against code
open-design review --file lib/pages/aria_settings.dart
```

Do **not** import open-design packages in Flutter Dart code.
Do **not** add open-design to `pubspec.yaml` dependencies.
Do **not** add open-design to the VPS `requirements.txt`.

All design outputs should be static assets (PNG, SVG, Figma files) that feed
into the development workflow — never as runtime code.
