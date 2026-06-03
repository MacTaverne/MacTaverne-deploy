# Bud — AI Business Agent for MacTaverne
**Product Requirements Document + Claude Build Prompt**

---

## Vision

Bud is a voice-first AI agent that lives permanently on your Mac. She has a name, a voice, and a persistent memory of everything MacTaverne. She can see your screen, hear you speak, read and write your files, manage your calendar and email, check your Stripe revenue, and spin up autonomous sub-agents to complete multi-step business tasks — all without you leaving the apps you're already in.

This is your personal operating system layer. Not a chatbot. An agent.

---

## The Build Prompt

> Paste this entire section into Claude Code to begin building Bud.

---

```
You are building Bud, a voice-first AI business agent that runs as a native macOS menu bar app for the user's company MacTaverne. 

Bud must:
- Live in the macOS menu bar (no Dock icon)
- Be always-on and voice-activated (push-to-talk: ctrl+option, or always-on wake word "Hey Bud")
- See the user's screen at all times using ScreenCaptureKit
- Speak back using ElevenLabs TTS (voice ID to be configured)
- Transcribe speech using Deepgram real-time WebSocket streaming
- Use Claude claude-opus-4-8 via Anthropic API as the reasoning engine
- Maintain persistent memory across sessions (local SQLite)
- Have full read/write access to the local file system
- Connect to: Google Calendar, Gmail, Stripe
- Spawn sub-agents to run autonomous background tasks

Build this as a Swift/SwiftUI macOS app (macOS 14.2+, Xcode 15+) with a Node.js/TypeScript Cloudflare Worker as the secure API proxy.

---

ARCHITECTURE

├── bud-app/                    # Swift/SwiftUI macOS app
│   ├── Core/
│   │   ├── BudAgent.swift       # Main agent coordinator (@MainActor ObservableObject)
│   │   ├── ScreenWatcher.swift       # ScreenCaptureKit screen capture + base64 encoding
│   │   ├── VoiceEngine.swift         # Deepgram WebSocket STT + ElevenLabs TTS orchestration
│   │   ├── MemoryStore.swift         # SQLite persistent memory (GRDB or raw sqlite3)
│   │   └── SubAgentRunner.swift      # Background task queue for autonomous agents
│   ├── Integrations/
│   │   ├── GoogleCalendarClient.swift
│   │   ├── GmailClient.swift
│   │   ├── StripeClient.swift
│   │   └── FileSystemAgent.swift     # Read/write/search/organize local files
│   ├── UI/
│   │   ├── MenuBarController.swift   # NSStatusItem menu bar presence
│   │   ├── OverlayWindow.swift       # Transparent HUD overlay (like HeyClicky cursor)
│   │   └── DashboardView.swift       # Full dashboard (cmd+shift+T to open)
│   └── Worker/                      # Cloudflare Worker proxy
│       ├── src/index.ts
│       └── wrangler.toml
└── bud-memory.db               # Persistent SQLite at ~/Library/Application Support/Bud/

---

CORE FEATURES TO BUILD (in order)

## Phase 1 — Voice + AI Core

1. Menu bar app with NSStatusItem
   - Shows animated waveform when listening
   - Shows pulsing dot when processing
   - Click to open dashboard

2. Push-to-talk voice activation
   - Hold ctrl+option to speak (same as HeyClicky)
   - Optional: always-on wake word detection using Apple's SFSpeechRecognizer

3. Deepgram real-time STT
   - WebSocket connection to wss://api.deepgram.com/v1/listen
   - Parameters: model=nova-3, language=en-US, punctuate=true, interim_results=true
   - Auth: "Authorization: Token YOUR_DEEPGRAM_API_KEY" header
   - Stream AVAudioPCMBuffer at 16kHz PCM16 (same as HeyClicky)
   - Worker proxy endpoint: POST /transcribe-token → returns Deepgram temp token

4. Claude API integration (streaming)
   - Model: claude-opus-4-8
   - System prompt includes: current time, current frontmost app, screen description, user name, business context
   - Conversation history: last 20 exchanges in SQLite
   - Worker proxy endpoint: POST /chat → proxies to Anthropic

5. ElevenLabs TTS
   - Model: eleven_flash_v2_5 (lowest latency)
   - Voice ID: configurable in settings
   - Stream audio back as it generates (don't wait for full response)
   - Worker proxy endpoint: POST /tts → proxies to ElevenLabs

6. Screen awareness
   - Capture all displays every 2s using ScreenCaptureKit (SCScreenshotManager)
   - Compress to JPEG 60% quality, max 1280px wide
   - Attach to every Claude message as vision content
   - Parse [POINT:x,y:label] tags in Claude responses to show overlay cursor

---

## Phase 2 — Memory + File System

7. Persistent memory (SQLite via GRDB)
   - Tables: conversations, facts, tasks, files_indexed
   - Auto-extract facts from conversations: "User's Stripe MRR is $X", "MacTaverne has Y customers"
   - Semantic search over memory using local embeddings (or keyword search fallback)
   - Bud remembers what you told her last week

8. File system agent
   - Read any file: text, PDF (via PDFKit), images, Word/Excel (via QuickLook text extraction)
   - Write/create files and folders on command
   - Search files by name or content: "Find all invoices from last month"
   - Organize: "Move all PDFs in Downloads to ~/Documents/MacTaverne/Invoices/"
   - Watch directories for changes (FSEvents)
   - Bud can draft documents and save them directly

---

## Phase 3 — Business Integrations

9. Google Calendar (OAuth2 + REST API)
   - Read: "What's on my calendar tomorrow?"
   - Create: "Schedule a call with Steve Friday at 2pm"
   - Update/delete events
   - Show conflicts: "I'm free Tuesday afternoon"
   - Store OAuth tokens securely in macOS Keychain

10. Gmail (OAuth2 + Gmail REST API)
    - Read latest emails: "Any urgent emails I should know about?"
    - Draft + send: "Email Steve the invoice"
    - Search: "Find emails about the venue deposit"
    - Labels and archive
    - Never send without explicit user confirmation ("Shall I send this?")

11. Stripe (Stripe API, read-only default)
    - MRR, revenue today/this month/YTD
    - Recent transactions
    - Customer lookup
    - Failed payments alert
    - "How much did MacTaverne make this month?"

---

## Phase 4 — Sub-Agents

12. SubAgentRunner — background autonomous task queue
    - User says: "Research the 5 best venues in Montreal for corporate events and put a summary in my Documents folder"
    - Bud creates a SubAgent task, runs it in background (using Claude + web search tool)
    - Notifies user when complete
    - Each sub-agent has: name, goal, tools available, max_steps, timeout
    - Sub-agent tools: web_search, read_file, write_file, send_email (with confirmation), calendar_create

13. Routine scheduler
    - "Every Monday at 9am, pull last week's Stripe revenue and email me a summary"
    - Stored in SQLite as cron-style jobs
    - Executed by background NSTimer + SubAgentRunner

---

CLOUDFLARE WORKER — src/index.ts

Build a single Cloudflare Worker with these proxy routes:
- POST /chat         → Anthropic Messages API (streaming SSE passthrough)
- POST /tts          → ElevenLabs TTS API (audio passthrough)
- GET  /transcribe-token → Deepgram token endpoint
- POST /stripe       → Stripe API (read-only queries)
- POST /gmail        → Gmail API (OAuth token from request, proxied)
- POST /calendar     → Google Calendar API (OAuth token from request, proxied)

Secrets (wrangler secret put):
- ANTHROPIC_API_KEY
- ELEVENLABS_API_KEY
- ELEVENLABS_VOICE_ID
- DEEPGRAM_API_KEY
- STRIPE_SECRET_KEY

---

SYSTEM PROMPT FOR BUD

```
You are Bud, a voice-first AI business agent for MacTaverne, owned by Timothy Robertson.

You live on Timothy's Mac as a menu bar assistant. You can see his screen, hear him speak, read and write his files, access his calendar, email, and Stripe revenue.

Your personality: confident, sharp, concise, warm. You're not a chatbot — you're an operator. When asked to do something, you do it. You don't ask unnecessary questions. When you need confirmation before sending an email or making a calendar change, you ask once, clearly.

You speak in short, natural sentences. Max 2-3 sentences per response unless explaining something complex.

Business context:
- Company: MacTaverne (event/tavern business in Montreal)
- Owner: Timothy Robertson
- Email: info@mactaverne.ca
- Tools available: file system, calendar, email, Stripe, web search, sub-agents

Current context:
- Date/time: {current_datetime}
- Frontmost app: {frontmost_app}
- Screen: {screen_description}
```

---

TECHNICAL REQUIREMENTS

- Swift 5.9+, SwiftUI, macOS 14.2+
- Concurrency: async/await + structured concurrency throughout (no callbacks)
- All API calls proxied through Cloudflare Worker (no keys in the binary)
- OAuth tokens stored in macOS Keychain (SecItemAdd/SecItemCopyMatching)
- SQLite via GRDB Swift package
- Audio: AVAudioEngine for capture, AVAudioPlayer/AVAudioPlayerNode for playback
- Permissions required: microphone, screen recording, accessibility, speech recognition
- Build as a single .xcodeproj (no Swift Package)
- Minimum target: macOS 14.2 (Sonoma)

---

EDGE CASES TO HANDLE

- Microphone permission denied → show settings deep link
- Screen recording denied → degrade gracefully (no vision, text only)
- No internet → queue actions, notify user
- ElevenLabs quota exceeded → fall back to AVSpeechSynthesizer silently
- Deepgram connection drops → reconnect with exponential backoff (1s, 2s, 4s, 8s, max 30s)
- Claude rate limited → queue and retry after delay, notify user
- Gmail/Calendar OAuth expired → trigger re-auth flow
- File too large for Claude context → chunk it, summarize sections
- User speaks while Bud is speaking → interrupt and listen
- Sub-agent stuck → timeout at 5 minutes, notify user with partial results
- Multiple simultaneous requests → queue, process in order, maintain context

---

SETUP INSTRUCTIONS TO INCLUDE IN README

1. Clone this repo
2. Run: bash install.sh
3. Install dependencies: cd worker && npm install
4. Set secrets: wrangler secret put ANTHROPIC_API_KEY (+ others)
5. Deploy worker: wrangler deploy
6. Open bud-app.xcodeproj in Xcode
7. Set your Apple signing team
8. Build & run (Cmd+R)
9. Grant permissions when prompted
10. Hold ctrl+option and say "Hey Bud, what's on my calendar today?"

---

START HERE

Begin by scaffolding the complete project structure. Create all directories and placeholder files. Then implement Phase 1 features in order (menu bar → voice → Claude → ElevenLabs). Each feature should be working and testable before moving to the next. 

Use the Cloudflare Worker as the secure proxy from day one — never put API keys in Swift code.

When you hit a build error, fix it before moving on. Do not skip errors.

After Phase 1 is complete and voice works end-to-end, check in with the user before starting Phase 2.
```

---

## Stack Summary

| Layer | Tech | Cost |
|---|---|---|
| AI reasoning | Claude claude-opus-4-8 | ~$0.05–0.25/session |
| Voice → text | Deepgram Nova-3 | $0.0043/min (free 200h trial) |
| Text → voice | ElevenLabs Flash v2.5 | $5/mo (Starter plan) |
| API proxy | Cloudflare Workers | Free tier |
| Memory | SQLite (local) | Free |
| Calendar/Email | Google OAuth | Free |
| Revenue data | Stripe API | Free |

**Monthly cost estimate: ~$5–15/month** for active daily use.

---

## Files in This Repo

- `install-heyclicky.sh` — install HeyClicky (free prototype, uses Gemini + Apple TTS/STT)
- `BUD_PRD.md` — this document

HeyClicky is the proof-of-concept. Bud is the full build.
