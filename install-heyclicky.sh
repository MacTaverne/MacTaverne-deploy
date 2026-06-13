#!/usr/bin/env bash
# HeyClicky — Free Stack Installer
# AI: Google Gemini Flash (free)  |  STT: Apple Speech (free)  |  TTS: Apple TTS (free)
# Run: bash <(curl -fsSL https://raw.githubusercontent.com/MacTaverne/MacTaverne-deploy/main/install-heyclicky.sh)

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*" >&2; }
info() { echo -e "${BLUE}[→]${NC} $*"; }

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║   HeyClicky — Free Stack Installer               ║"
echo "║   AI: Gemini  |  Voice: Apple TTS + STT          ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# ── 1. macOS ──────────────────────────────────────────────────────────────────
info "Checking macOS..."
MACOS_VER=$(sw_vers -productVersion)
MACOS_MAJOR=$(echo "$MACOS_VER" | cut -d. -f1)
MACOS_MINOR=$(echo "$MACOS_VER" | cut -d. -f2)
if [[ "$MACOS_MAJOR" -lt 14 ]] || { [[ "$MACOS_MAJOR" -eq 14 ]] && [[ "$MACOS_MINOR" -lt 2 ]]; }; then
  err "macOS 14.2+ required (you have $MACOS_VER)."
  exit 1
fi
log "macOS $MACOS_VER — OK"

# ── 2. Xcode ──────────────────────────────────────────────────────────────────
info "Checking Xcode..."
if ! xcode-select -p &>/dev/null; then
  warn "Installing Xcode command-line tools..."
  xcode-select --install
  echo "   Re-run this script after the installer completes."
  exit 0
fi
XCODE_VER=$(xcodebuild -version 2>/dev/null | head -1 | awk '{print $2}' || echo "unknown")
log "Xcode $XCODE_VER — OK"

# ── 3. Node.js ────────────────────────────────────────────────────────────────
info "Checking Node.js..."
if ! command -v node &>/dev/null; then
  if ! command -v brew &>/dev/null; then
    info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
  brew install node
fi
NODE_MAJOR=$(node --version | tr -d 'v' | cut -d. -f1)
if [[ "$NODE_MAJOR" -lt 18 ]]; then
  warn "Node.js 18+ required. Upgrading..."
  brew upgrade node || brew install node
fi
log "Node.js $(node --version) — OK"

# ── 4. Wrangler ───────────────────────────────────────────────────────────────
info "Checking Wrangler..."
if ! command -v wrangler &>/dev/null; then
  npm install -g wrangler
fi
log "Wrangler — OK"

# ── 5. Clone / update ─────────────────────────────────────────────────────────
INSTALL_DIR="$HOME/heyclicky"
info "Cloning HeyClicky into $INSTALL_DIR..."
if [[ -d "$INSTALL_DIR/.git" ]]; then
  warn "Directory exists — pulling latest..."
  git -C "$INSTALL_DIR" pull --ff-only || true
else
  git clone https://github.com/farzaa/clicky.git "$INSTALL_DIR"
fi
log "Repository ready at $INSTALL_DIR"

# ── 6. Apply free-stack patches ───────────────────────────────────────────────
info "Applying free-stack patches (Gemini + Apple TTS/STT)..."

# 6a. New Cloudflare Worker — proxies /chat to Gemini Flash (no other routes needed)
cat > "$INSTALL_DIR/worker/src/index.ts" << '_TSEOF_'
// Clicky proxy — Gemini Flash edition
// POST /chat → Google Gemini 2.0 Flash (streaming), translated to Anthropic SSE format

interface Env {
  GEMINI_API_KEY: string;
}

const GEMINI_MODEL = "gemini-2.0-flash";

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method !== "POST") {
      return new Response("Method not allowed", { status: 405 });
    }
    const path = new URL(request.url).pathname;
    try {
      if (path === "/chat") return handleChat(request, env);
    } catch (e) {
      return new Response(JSON.stringify({ error: String(e) }), {
        status: 500,
        headers: { "content-type": "application/json" },
      });
    }
    return new Response("Not found", { status: 404 });
  },
};

function handleChat(request: Request, env: Env): Response {
  const { readable, writable } = new TransformStream<Uint8Array, Uint8Array>();
  const writer = writable.getWriter();
  const enc = new TextEncoder();
  const dec = new TextDecoder();

  const sse = (event: string, data: unknown) =>
    writer.write(enc.encode(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`));

  (async () => {
    try {
      const anthropic = await request.json() as {
        messages: Array<{ role: string; content: string | Array<{ type: string; text?: string }> }>;
        system?: string;
        max_tokens?: number;
      };

      const contents = anthropic.messages.map((m) => ({
        role: m.role === "assistant" ? "model" : "user",
        parts: [{
          text: typeof m.content === "string"
            ? m.content
            : m.content.filter((c) => c.type === "text").map((c) => c.text ?? "").join(""),
        }],
      }));

      const body: Record<string, unknown> = {
        contents,
        generationConfig: { maxOutputTokens: anthropic.max_tokens ?? 2048 },
      };
      if (anthropic.system) {
        body.systemInstruction = { parts: [{ text: anthropic.system }] };
      }

      const url = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:streamGenerateContent?alt=sse&key=${env.GEMINI_API_KEY}`;
      const resp = await fetch(url, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(body),
      });

      if (!resp.ok) {
        const errText = await resp.text();
        console.error(`Gemini error ${resp.status}: ${errText}`);
        await writer.write(enc.encode(`event: error\ndata: ${errText}\n\n`));
        return;
      }

      // Anthropic SSE preamble
      await sse("message_start", {
        type: "message_start",
        message: { id: "msg_gemini", type: "message", role: "assistant", content: [] },
      });
      await sse("content_block_start", {
        type: "content_block_start", index: 0, content_block: { type: "text", text: "" },
      });

      // Stream Gemini → Anthropic delta events
      const reader = resp.body!.getReader();
      let buf = "";
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        buf += dec.decode(value, { stream: true });
        const lines = buf.split("\n");
        buf = lines.pop() ?? "";
        for (const line of lines) {
          if (!line.startsWith("data: ")) continue;
          const json = line.slice(6).trim();
          if (!json || json === "[DONE]") continue;
          try {
            const chunk = JSON.parse(json);
            const text: string | undefined = chunk?.candidates?.[0]?.content?.parts?.[0]?.text;
            if (text) {
              await sse("content_block_delta", {
                type: "content_block_delta",
                index: 0,
                delta: { type: "text_delta", text },
              });
            }
          } catch { /* skip malformed */ }
        }
      }

      await sse("content_block_stop", { type: "content_block_stop", index: 0 });
      await sse("message_delta", {
        type: "message_delta",
        delta: { stop_reason: "end_turn" },
        usage: { output_tokens: 0 },
      });
      await sse("message_stop", { type: "message_stop" });
    } catch (e) {
      console.error("handleChat error:", e);
    } finally {
      await writer.close();
    }
  })();

  return new Response(readable, {
    headers: { "content-type": "text/event-stream", "cache-control": "no-cache" },
  });
}
_TSEOF_

# 6b. Simplified wrangler.toml — no ElevenLabs voice ID needed
cat > "$INSTALL_DIR/worker/wrangler.toml" << '_TOMLEOF_'
name = "clicky-proxy"
main = "src/index.ts"
compatibility_date = "2024-01-01"
_TOMLEOF_

# 6c. Append AppleTTSClient to ElevenLabsTTSClient.swift (already in Xcode target)
cat >> "$INSTALL_DIR/leanring-buddy/ElevenLabsTTSClient.swift" << '_SWIFTEOF_'

// MARK: - AppleTTSClient (free, no API key — uses macOS AVSpeechSynthesizer)

@MainActor
final class AppleTTSClient: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var finishContinuation: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speakText(_ text: String) async throws {
        stopPlayback()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.50
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        synthesizer.speak(utterance)
        await withCheckedContinuation { continuation in
            finishContinuation = continuation
        }
    }

    var isPlaying: Bool { synthesizer.isSpeaking }

    func stopPlayback() {
        synthesizer.stopSpeaking(at: .immediate)
        let c = finishContinuation
        finishContinuation = nil
        c?.resume()
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            let c = self?.finishContinuation
            self?.finishContinuation = nil
            c?.resume()
        }
    }
}
_SWIFTEOF_

# 6d. Add Speech import + AppleSpeechTranscriptionProvider to AssemblyAI file
#     (appending to an existing Xcode-tracked file avoids pbxproj edits)
INSTALL_DIR="$INSTALL_DIR" python3 << '_PYEOF_'
import os
path = os.environ['INSTALL_DIR'] + '/leanring-buddy/AssemblyAIStreamingTranscriptionProvider.swift'
with open(path) as f:
    c = f.read()
# Ensure Speech is imported at the top
if 'import Speech' not in c:
    c = 'import Speech\n' + c
with open(path, 'w') as f:
    f.write(c)
_PYEOF_

cat >> "$INSTALL_DIR/leanring-buddy/AssemblyAIStreamingTranscriptionProvider.swift" << '_SWIFTEOF_'

// MARK: - AppleSpeechTranscriptionProvider (free, on-device, no API key)

final class AppleSpeechTranscriptionProvider: BuddyTranscriptionProvider {
    let displayName = "Apple Speech"
    let requiresSpeechRecognitionPermission = true
    var isConfigured: Bool { true }
    var unavailableExplanation: String? { nil }

    func startStreamingSession(
        keyterms: [String],
        onTranscriptUpdate: @escaping (String) -> Void,
        onFinalTranscriptReady: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) async throws -> any BuddyStreamingTranscriptionSession {
        let session = AppleSpeechSession(
            onTranscriptUpdate: onTranscriptUpdate,
            onFinalTranscriptReady: onFinalTranscriptReady,
            onError: onError
        )
        try await session.open()
        return session
    }
}

private final class AppleSpeechSession: NSObject, BuddyStreamingTranscriptionSession {
    let finalTranscriptFallbackDelaySeconds: TimeInterval = 1.5

    private let onTranscriptUpdate: (String) -> Void
    private let onFinalTranscriptReady: (String) -> Void
    private let onError: (Error) -> Void

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latestTranscript = ""
    private var cancelled = false

    init(
        onTranscriptUpdate: @escaping (String) -> Void,
        onFinalTranscriptReady: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        self.onTranscriptUpdate = onTranscriptUpdate
        self.onFinalTranscriptReady = onFinalTranscriptReady
        self.onError = onError
    }

    func open() async throws {
        let rec = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let rec, rec.isAvailable else {
            throw NSError(domain: "AppleSpeech", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Speech recognizer unavailable"])
        }
        recognizer = rec
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req
        task = rec.recognitionTask(with: req) { [weak self] result, error in
            guard let self, !self.cancelled else { return }
            if let error {
                if (error as NSError).code == 301 { return } // normal cancel
                self.onError(error)
                return
            }
            if let result {
                let text = result.bestTranscription.formattedString
                self.latestTranscript = text
                self.onTranscriptUpdate(text)
            }
        }
    }

    func appendAudioBuffer(_ audioBuffer: AVAudioPCMBuffer) {
        request?.append(audioBuffer)
    }

    func requestFinalTranscript() {
        request?.endAudio()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, !self.cancelled else { return }
            self.onFinalTranscriptReady(self.latestTranscript)
        }
    }

    func cancel() {
        cancelled = true
        task?.cancel()
        request?.endAudio()
        task = nil
        request = nil
    }
}
_SWIFTEOF_

# 6e. Patch CompanionManager.swift — swap ElevenLabsTTSClient → AppleTTSClient
INSTALL_DIR="$INSTALL_DIR" python3 << '_PYEOF_'
import re, os
path = os.environ['INSTALL_DIR'] + '/leanring-buddy/CompanionManager.swift'
with open(path) as f:
    c = f.read()
c = c.replace(': ElevenLabsTTSClient =', ': AppleTTSClient =')
c = re.sub(r'ElevenLabsTTSClient\(proxyURL:[^)]+\)', 'AppleTTSClient()', c)
with open(path, 'w') as f:
    f.write(c)
print('Patched CompanionManager.swift')
_PYEOF_

# 6f. Patch BuddyDictationManager.swift — swap provider factory → AppleSpeechTranscriptionProvider
INSTALL_DIR="$INSTALL_DIR" python3 << '_PYEOF_'
import os
path = os.environ['INSTALL_DIR'] + '/leanring-buddy/BuddyDictationManager.swift'
with open(path) as f:
    c = f.read()
c = c.replace(
    'BuddyTranscriptionProviderFactory.makeDefaultProvider()',
    'AppleSpeechTranscriptionProvider()'
)
with open(path, 'w') as f:
    f.write(c)
print('Patched BuddyDictationManager.swift')
_PYEOF_

log "Free-stack patches applied"

# ── 7. Gemini API key ─────────────────────────────────────────────────────────
echo ""
echo "Only ONE API key needed — Google Gemini (free tier)."
echo "Get yours at: https://aistudio.google.com/apikey"
echo ""
read -rp "Google Gemini API key: " GEMINI_KEY
echo ""

# ── 8. Deploy Cloudflare Worker ───────────────────────────────────────────────
WORKER_DIR="$INSTALL_DIR/worker"
info "Installing worker dependencies..."
cd "$WORKER_DIR"
npm install

info "Storing Gemini key in Cloudflare (browser login may appear)..."
echo "$GEMINI_KEY" | wrangler secret put GEMINI_API_KEY --name clicky-proxy

info "Deploying Worker..."
WORKER_URL=$(wrangler deploy 2>&1 | grep -o 'https://[a-zA-Z0-9._-]*\.workers\.dev' | head -1)

if [[ -z "$WORKER_URL" ]]; then
  err "Could not detect Worker URL from deploy output."
  err "Manually replace the placeholder URL in CompanionManager.swift"
  exit 1
fi
log "Worker deployed at $WORKER_URL"

# ── 9. Patch Worker URL into Swift ────────────────────────────────────────────
info "Patching Swift source with Worker URL..."
cd "$INSTALL_DIR"

for F in \
  "leanring-buddy/CompanionManager.swift" \
  "leanring-buddy/AssemblyAIStreamingTranscriptionProvider.swift"; do
  if [[ -f "$F" ]]; then
    sed -i '' "s|https://[a-zA-Z0-9._-]*\.workers\.dev|$WORKER_URL|g" "$F"
    log "Patched $F"
  fi
done

# ── 10. Open Xcode ────────────────────────────────────────────────────────────
XCODEPROJ=$(find "$INSTALL_DIR" -maxdepth 2 -name "*.xcodeproj" | head -1)
echo ""
if [[ -n "$XCODEPROJ" ]]; then
  log "All done!"
  echo ""
  echo "╔══════════════════════════════════════════════════════════╗"
  echo "║  Next steps:                                             ║"
  echo "║  1. Xcode opens — select your Apple signing team         ║"
  echo "║  2. Press Cmd+R to build and run                         ║"
  echo "║  3. Grant: microphone, accessibility, speech recognition ║"
  echo "║  4. HeyClicky appears in your menu bar                   ║"
  echo "║                                                          ║"
  echo "║  Cost: \$0/month                                          ║"
  echo "╚══════════════════════════════════════════════════════════╝"
  echo ""
  open "$XCODEPROJ"
else
  warn "Xcode project not found. Open manually from $INSTALL_DIR"
fi
