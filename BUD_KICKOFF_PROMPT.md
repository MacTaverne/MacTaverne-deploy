# Bud — New Session Kickoff Prompt

Paste this into a fresh Claude Code session to start building.

---

```
Read the file BUD_BUILD_PLAN.md in this repo (MacTaverne/MacTaverne-deploy).
That is the approved plan. Do not deviate from it without asking.

We are building Bud — a voice-first AI business agent for MacTaverne that lives
in the macOS menu bar. We are in Phase 1: Voice Core.

Starting point: fork the HeyClicky repo (https://github.com/farzaa/clicky) 
into ~/MacTaverne/bud on the user's Mac.

Phase 1 build order (do not skip ahead):
1. Clone farzaa/clicky into ~/MacTaverne/bud
2. Rename the Xcode project from "leanring-buddy" to "bud-app"
3. Create a new GitHub repo MacTaverne/bud and push to it
4. Update the system prompt to Bud's personality (see BUD_PRD.md)
5. Change wake phrase from ctrl+option to ctrl+option (keep same) + update all
   UI strings from "Clicky" → "Bud"
6. Wire in the AppleTTSClient (already in BUD_PRD.md) behind a BudTTSProvider protocol
7. Wire in the AppleSpeechTranscriptionProvider (already in BUD_PRD.md)
8. Set up the Cloudflare Worker with a single /chat route → Anthropic API
9. Ask the user to: get their Anthropic API key, run wrangler deploy, and
   set the worker URL in Xcode
10. Build and test: "Hey Bud, what's on my screen?"

Keys the user needs for Phase 1:
- ANTHROPIC_API_KEY (console.anthropic.com)
- Cloudflare account (free, wrangler will prompt to log in)

Do NOT build file system, calendar, Gmail, Stripe, or Veloce integrations yet.
Those are Phase 2 and 3. Build Phase 1 end-to-end first.

Ask the user to confirm each milestone works before moving to the next step.
```
