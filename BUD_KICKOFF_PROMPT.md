# Bud — New Session Kickoff Prompt
Paste this into a fresh Claude Code session to start building.

---

```
We are building Bud — a voice-first AI business agent for MacTaverne that lives
in the macOS menu bar. The owner is Timothy Robertson (info@mactaverne.ca).

IMPORTANT DECISIONS (do not change these):
- Stack: Electron + Node.js (NOT Swift, NOT HeyClicky)
- IDE: VS Code (no Xcode required)
- AI brain: Claude claude-sonnet-4-6 via Anthropic API
- Voice out (TTS): macOS native `say` command via child_process → swappable later
- Voice in (STT): OpenAI Whisper via node (local model, free)
- Wake phrase: ctrl+option hold to talk, "Hey Bud" always-on detection
- API proxy: Cloudflare Worker (free tier, keeps keys out of app)
- Project location: ~/MacTaverne/bud on Mac, GitHub repo: MacTaverne/bud
- Memory: SQLite (better-sqlite3) stored at ~/Library/Application Support/Bud/

Read BUD_BUILD_PLAN.md in this repo (MacTaverne/MacTaverne-deploy) for the full
approved integration plan. Do not deviate without asking.

---

PHASE 1 — Build this first, nothing else:

Project structure to scaffold:
```
~/MacTaverne/bud/
├── package.json
├── .env.example
├── main.js                  # Electron main process — menu bar app
├── preload.js               # Electron preload bridge
├── renderer/
│   ├── index.html           # Dashboard UI (cmd+shift+B to show)
│   └── renderer.js          # Dashboard logic
├── src/
│   ├── bud.js               # Core agent — orchestrates everything
│   ├── voice.js             # STT (Whisper) + TTS (say command)
│   ├── screen.js            # Screen capture (screenshot-desktop)
│   ├── memory.js            # SQLite conversation + facts store
│   ├── claude.js            # Anthropic API streaming client
│   └── hotkey.js            # ctrl+option global hotkey listener
└── worker/
    ├── src/index.ts         # Cloudflare Worker — proxies /chat to Anthropic
    └── wrangler.toml
```

PHASE 1 features (build in this order):
1. Electron menu bar app — NSStatusItem equivalent (Tray icon, no Dock icon)
2. Global hotkey: ctrl+option → start recording, release → send to Claude
3. Screen capture: grab screenshot on each request, attach to Claude message
4. Claude streaming via Cloudflare Worker (/chat → Anthropic)
5. TTS response: pipe Claude text to macOS `say` command (free, built-in)
6. SQLite memory: save conversation history, load on startup
7. Dashboard: cmd+shift+B opens a simple window showing last 10 exchanges

PHASE 1 milestone: Hold ctrl+option → speak → Bud sees screen → Claude responds
→ macOS speaks the answer. Zero API keys except Anthropic.

---

PHASE 2 (after Phase 1 is working):
- File system agent (read/write/organize local files)

PHASE 3 (after Phase 2):
- Google Calendar (OAuth2)
- Gmail (OAuth2)
- Stripe (read-only API)
- Veloce POS (REST API — user has credentials)

PHASE 4:
- Sub-agents and scheduled routines
- TTS upgrade (Kokoro or ElevenLabs)
- Always-on wake word

---

BUD SYSTEM PROMPT (use this in claude.js):

You are Bud, a voice-first AI business agent for MacTaverne, owned by Timothy Robertson.

You live on Timothy's Mac as a menu bar assistant. You can see his screen, hear him
speak, and help run his business. MacTaverne is an event/tavern business in Montreal.

Your personality: confident, sharp, concise, warm. You're an operator, not a chatbot.
When asked to do something, you do it. Max 2-3 sentences per voice response unless
explaining something complex. No markdown in voice responses — plain spoken English only.

Current context injected each message:
- Date/time: {datetime}
- Frontmost app: {frontmost_app}
- Screen: {screen_description}

---

CLOUDFLARE WORKER (worker/src/index.ts):
Single route: POST /chat → stream to Anthropic Messages API
Include full SSE passthrough. Secret: ANTHROPIC_API_KEY.

---

API KEYS NEEDED FOR PHASE 1:
- ANTHROPIC_API_KEY (console.anthropic.com) — only paid piece (~$5-15/mo)
- Cloudflare account (free, wrangler login)
- Everything else in Phase 1 is free

---

START:
1. mkdir -p ~/MacTaverne/bud and scaffold the full project structure
2. Create GitHub repo MacTaverne/bud
3. Implement Phase 1 features in order
4. When worker is ready, ask user to run: cd ~/MacTaverne/bud/worker && wrangler deploy
5. When app is ready, ask user to run: npm install && npm start
6. Test: hold ctrl+option and ask "Hey Bud, what's on my screen?"
7. Confirm it works before moving to Phase 2

Ask the user for their ANTHROPIC_API_KEY before starting the worker setup.
Do NOT start Phase 2 until Phase 1 is fully working.
```
