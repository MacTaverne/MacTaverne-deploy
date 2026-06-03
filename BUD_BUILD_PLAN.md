# Bud — Full Build Plan
**MacTaverne AI Business Agent | Pre-build approval document**

---

## Decisions Locked In

| Decision | Choice | Notes |
|---|---|---|
| Base | Fork HeyClicky | Keep screen awareness, overlay, push-to-talk scaffolding |
| AI brain | Claude claude-sonnet-4-6 | Best reasoning for multi-step business tasks |
| Voice out (TTS) | Apple TTS → swappable | Start free, upgrade to Kokoro/GitHub model any time |
| Voice in (STT) | Apple Speech (on-device) | Free, real-time, no API key |
| Wake phrase | "Hey Bud" + ctrl+option hold | Both modes active |
| Project location | `~/MacTaverne/bud` | GitHub: `MacTaverne/bud` |
| API proxy | Cloudflare Worker (free tier) | No keys in Swift binary |

---

## What Bud Will Do (Phase 1 — First Working Build)

When complete, you hold ctrl+option (or say "Hey Bud") and Bud:

1. **Hears you** via Apple Speech (real-time, on-device)
2. **Sees your screen** via ScreenCaptureKit
3. **Thinks** with Claude claude-sonnet-4-6
4. **Speaks back** via Apple TTS (Siri-quality voice, no API needed)
5. **Remembers** context across sessions (local SQLite)
6. **Lives in the menu bar** — no Dock icon, always available

---

## Project Structure

```
~/MacTaverne/
├── bud/                              ← main project
│   ├── bud-app/
│   │   ├── bud-app.xcodeproj
│   │   └── bud-app/
│   │       ├── Core/
│   │       │   ├── BudAgent.swift          (main coordinator)
│   │       │   ├── ScreenWatcher.swift     (ScreenCaptureKit)
│   │       │   ├── VoiceEngine.swift       (STT + TTS orchestration)
│   │       │   ├── MemoryStore.swift       (SQLite via GRDB)
│   │       │   └── TTSProvider.swift       (swappable TTS protocol)
│   │       ├── Integrations/
│   │       │   ├── FileSystemAgent.swift
│   │       │   ├── GoogleCalendarClient.swift
│   │       │   ├── GmailClient.swift
│   │       │   ├── StripeClient.swift
│   │       │   └── VeloceClient.swift      (POS data)
│   │       ├── UI/
│   │       │   ├── MenuBarController.swift
│   │       │   ├── OverlayWindow.swift     (HUD + cursor pointer)
│   │       │   └── DashboardView.swift     (cmd+shift+B to open)
│   │       └── Resources/
│   │           └── bud-app-Info.plist
│   └── worker/
│       ├── src/index.ts                    (Cloudflare proxy)
│       └── wrangler.toml
└── heyclicky/                        ← prototype (keep as reference)
```

GitHub repos:
- `MacTaverne/bud` — the full Bud build (new repo)
- `MacTaverne/MacTaverne-deploy` — this repo (PRD, installer scripts)

---

## Build Phases

### Phase 1 — Voice Core (builds first, ~2-3 hours with Claude)
Everything needed for a working "Hey Bud, what time is it?" demo.

- [ ] Fork HeyClicky into `~/MacTaverne/bud`
- [ ] Rename project to `bud-app`
- [ ] Update system prompt: Bud personality, MacTaverne context
- [ ] Swap wake word to "Hey Bud"
- [ ] Wire in `AppleTTSClient` (already built, needs import)
- [ ] Wire in `AppleSpeechTranscriptionProvider` (already built, needs import)
- [ ] Set up Cloudflare Worker with Anthropic proxy (`/chat` route)
- [ ] Local SQLite memory (GRDB): conversation history, facts about MacTaverne
- [ ] Menu bar: shows waveform when listening, dot when thinking
- [ ] Dashboard: cmd+shift+B opens a full panel

**Milestone**: Say "Hey Bud, summarize what's on my screen" → Bud sees screen, responds with Claude, speaks with Apple TTS.

---

### Phase 2 — File System (adds local intelligence)

- [ ] `FileSystemAgent.swift` — read/write/search/organize
- [ ] Read text files, PDFs (PDFKit), images
- [ ] Natural language file commands:
  - "Find all PDFs in Downloads from this month"
  - "Create a folder called Q3 Reports in Documents"
  - "Move all invoices to MacTaverne/Finance"
- [ ] Directory watcher (FSEvents) — Bud notices new files
- [ ] Draft + save documents: "Write a welcome email for new staff and save it to my Desktop"

**Milestone**: "Hey Bud, find all my invoices and tell me which ones are from Veloce this year"

---

### Phase 3 — Business Integrations

#### 3a. Google Calendar + Gmail (OAuth2)
- [ ] Google OAuth client setup (Google Cloud Console — we'll walk through this)
- [ ] Calendar: read events, create/update/delete
- [ ] Gmail: read inbox, draft + send (confirm before sending)
- [ ] OAuth tokens in macOS Keychain (secure, persistent login)

**Milestone**: "Hey Bud, do I have anything on my calendar tomorrow?" / "Draft a reply to the last email from our venue supplier"

#### 3b. Stripe (read-only)
- [ ] Stripe API — balance, charges, MRR, recent transactions
- [ ] Natural queries: "How much did we make this week?" / "Did anyone pay their tab?"
- [ ] Worker route: `POST /stripe`

**Milestone**: "Hey Bud, what's MacTaverne's revenue this month?"

#### 3c. Veloce POS ✓ Full API access confirmed
- [ ] Locate Veloce API docs (user has credentials)
- [ ] Auth: REST API with API key / credentials
- [ ] Endpoints needed:
  - Sales & revenue reports (daily revenue, sales by hour, table totals)
  - Menu items & orders (what sold, quantities, top items)
  - Historical reporting (end-of-day, weekly, monthly summaries)
- [ ] Worker route: `POST /veloce` (proxy with Veloce credentials as secrets)
- [ ] Store Veloce API key in Cloudflare Worker secrets (never in Swift binary)

**Milestone**: "Hey Bud, what were our top 5 selling items last night?" / "How much did we gross this week vs last week?"

---

### Phase 4 — Advanced (after Phase 3 is stable)

- [ ] Sub-agents: "Research the top 10 Montreal event suppliers and put a list in my Documents"
- [ ] Scheduled routines: "Every Monday morning, send me last week's Stripe + Veloce summary"
- [ ] Always-on wake word (Whisper.cpp locally — upgrade STT for wake-word detection)
- [ ] TTS upgrade: swap Apple TTS for Kokoro or another GitHub model
- [ ] Web search tool for Claude

---

## Swappable TTS — How the Upgrade Path Works

Bud's voice is behind a `BudTTSProvider` protocol. Swapping it requires changing one line in `VoiceEngine.swift`:

```swift
// Phase 1 (right now — free)
let tts: BudTTSProvider = AppleTTSClient()

// Future upgrade (same protocol, different impl)
let tts: BudTTSProvider = KokoroTTSClient()   // local neural voice
let tts: BudTTSProvider = OpenAITTSClient()   // cloud, ~pennies/day
let tts: BudTTSProvider = ElevenLabsClient()  // best quality, $5/mo
```

We'll document the upgrade steps in the README. No architectural changes needed.

---

## API Keys Needed

| Service | Key | Where to get | Cost |
|---|---|---|---|
| Anthropic | `ANTHROPIC_API_KEY` | console.anthropic.com | ~$5-15/mo |
| Stripe | `STRIPE_SECRET_KEY` | dashboard.stripe.com/apikeys | Free |
| Google OAuth | Client ID + Secret | console.cloud.google.com | Free |
| Veloce | API key (if available) | Contact Veloce support | Free |
| Cloudflare | Auto via Wrangler login | cloudflare.com | Free |

No ElevenLabs or Deepgram keys needed for Phase 1.

---

## One Open Question Before We Start

**Veloce**: To build the Veloce integration in Phase 3, we need to know:
1. Do you have API documentation or credentials from Veloce?
2. Or do you just log into a web dashboard at a URL like `app.veloce.ca`?

This determines whether it's a clean API integration or we need to use browser-based extraction. Either way we can do it — just different approaches.

---

## What We Are NOT Building Yet (Phase 1)

- Mobile app (iPhone/iPad)
- Multi-user / multi-device sync
- Payments or financial actions via Stripe
- Custom wake word model training
- MacTaverne website / SEO integration (Google Search Console) — Phase 4
- MacTaverne OS web app integration — scope TBD once web app is defined

---

## Ready to Build?

Once you approve this plan (or request changes), the build order is:

```
Step 1: Create MacTaverne/bud GitHub repo
Step 2: Fork HeyClicky → ~/MacTaverne/bud
Step 3: Rename, rebrand, update system prompt
Step 4: Wire TTS + STT + Claude
Step 5: Deploy worker (you run one command)
Step 6: Build in Xcode → Bud is live
Step 7: Add file system, then integrations one by one
```

**Nothing is deployed until you say go.**
