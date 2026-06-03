#!/usr/bin/env bash
# HeyClicky (Clicky) installer for macOS
# Source: https://github.com/farzaa/clicky
# Run with: bash install-heyclicky.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*" >&2; }
info() { echo -e "${BLUE}[→]${NC} $*"; }

echo ""
echo "╔════════════════════════════════════════╗"
echo "║        HeyClicky Mac Installer         ║"
echo "╚════════════════════════════════════════╝"
echo ""

# ── 1. macOS version check ────────────────────────────────────────────────────
info "Checking macOS version..."
MACOS_VER=$(sw_vers -productVersion)
MACOS_MAJOR=$(echo "$MACOS_VER" | cut -d. -f1)
MACOS_MINOR=$(echo "$MACOS_VER" | cut -d. -f2)
if [[ "$MACOS_MAJOR" -lt 14 ]] || { [[ "$MACOS_MAJOR" -eq 14 ]] && [[ "$MACOS_MINOR" -lt 2 ]]; }; then
  err "macOS 14.2 (Sonoma) or later is required. You have $MACOS_VER."
  exit 1
fi
log "macOS $MACOS_VER — OK"

# ── 2. Xcode command-line tools ───────────────────────────────────────────────
info "Checking Xcode..."
if ! xcode-select -p &>/dev/null; then
  warn "Xcode command-line tools not found. Installing..."
  xcode-select --install
  echo "   After the installer finishes, re-run this script."
  exit 0
fi
XCODE_VER=$(xcodebuild -version 2>/dev/null | head -1 | awk '{print $2}' || echo "unknown")
log "Xcode $XCODE_VER — OK"

# ── 3. Node.js ────────────────────────────────────────────────────────────────
info "Checking Node.js..."
if ! command -v node &>/dev/null; then
  warn "Node.js not found. Installing via Homebrew..."
  if ! command -v brew &>/dev/null; then
    info "Installing Homebrew first..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
  brew install node
fi
NODE_VER=$(node --version | tr -d 'v')
NODE_MAJOR=$(echo "$NODE_VER" | cut -d. -f1)
if [[ "$NODE_MAJOR" -lt 18 ]]; then
  warn "Node.js 18+ required (you have $NODE_VER). Upgrading via Homebrew..."
  brew upgrade node || brew install node
fi
log "Node.js $(node --version) — OK"

# ── 4. Wrangler (Cloudflare CLI) ──────────────────────────────────────────────
info "Checking Wrangler CLI..."
if ! command -v wrangler &>/dev/null; then
  info "Installing Wrangler globally..."
  npm install -g wrangler
fi
log "Wrangler $(wrangler --version 2>/dev/null | head -1) — OK"

# ── 5. Clone repo ─────────────────────────────────────────────────────────────
INSTALL_DIR="$HOME/heyclicky"
info "Cloning HeyClicky into $INSTALL_DIR..."
if [[ -d "$INSTALL_DIR/.git" ]]; then
  warn "Directory already exists. Pulling latest changes..."
  git -C "$INSTALL_DIR" pull --ff-only
else
  git clone https://github.com/farzaa/clicky.git "$INSTALL_DIR"
fi
log "Repository ready at $INSTALL_DIR"

# ── 6. Collect API keys ───────────────────────────────────────────────────────
echo ""
echo "You need API keys from three services to continue."
echo "Create free/paid accounts at:"
echo "  • https://console.anthropic.com       (Anthropic — Claude)"
echo "  • https://www.assemblyai.com          (AssemblyAI — speech-to-text)"
echo "  • https://elevenlabs.io               (ElevenLabs — text-to-speech)"
echo ""

read -rp "Anthropic API key  : " ANTHROPIC_KEY
read -rp "AssemblyAI API key : " ASSEMBLYAI_KEY
read -rp "ElevenLabs API key : " ELEVENLABS_KEY
read -rp "ElevenLabs Voice ID (leave blank for default): " ELEVENLABS_VOICE_ID
ELEVENLABS_VOICE_ID="${ELEVENLABS_VOICE_ID:-pNInz6obpgDQGcFmaJgB}"

echo ""

# ── 7. Deploy Cloudflare Worker ───────────────────────────────────────────────
WORKER_DIR="$INSTALL_DIR/worker"
info "Setting up Cloudflare Worker in $WORKER_DIR..."

cd "$WORKER_DIR"
npm install

info "Storing API secrets in Cloudflare (you may be prompted to log in)..."
echo "$ANTHROPIC_KEY"   | wrangler secret put ANTHROPIC_API_KEY   --name clicky-proxy
echo "$ASSEMBLYAI_KEY"  | wrangler secret put ASSEMBLYAI_API_KEY  --name clicky-proxy
echo "$ELEVENLABS_KEY"  | wrangler secret put ELEVENLABS_API_KEY  --name clicky-proxy

# Inject voice ID into wrangler.toml
if grep -q 'ELEVENLABS_VOICE_ID' wrangler.toml 2>/dev/null; then
  sed -i '' "s|ELEVENLABS_VOICE_ID.*|ELEVENLABS_VOICE_ID = \"$ELEVENLABS_VOICE_ID\"|" wrangler.toml
else
  echo "ELEVENLABS_VOICE_ID = \"$ELEVENLABS_VOICE_ID\"" >> wrangler.toml
fi

info "Deploying Worker..."
WORKER_URL=$(wrangler deploy 2>&1 | grep -o 'https://[a-zA-Z0-9._-]*\.workers\.dev' | head -1)

if [[ -z "$WORKER_URL" ]]; then
  err "Could not detect Worker URL from deploy output. Check 'wrangler deploy' output above."
  err "Manually set your worker URL in CompanionManager.swift and AssemblyAIStreamingTranscriptionProvider.swift"
  exit 1
fi

log "Worker deployed at $WORKER_URL"

# ── 8. Patch Swift source with Worker URL ─────────────────────────────────────
info "Patching Swift source files with your Worker URL..."
cd "$INSTALL_DIR"

SWIFT_FILES=(
  "leanring-buddy/CompanionManager.swift"
  "leanring-buddy/AssemblyAIStreamingTranscriptionProvider.swift"
)

PATCHED=0
for F in "${SWIFT_FILES[@]}"; do
  if [[ -f "$F" ]]; then
    sed -i '' "s|https://[a-zA-Z0-9._-]*\.workers\.dev|$WORKER_URL|g" "$F"
    log "Patched $F"
    PATCHED=$((PATCHED + 1))
  fi
done

if [[ "$PATCHED" -eq 0 ]]; then
  warn "Swift files not found at expected paths. You may need to manually set:"
  warn "  Worker URL: $WORKER_URL"
  warn "  In: CompanionManager.swift and AssemblyAIStreamingTranscriptionProvider.swift"
fi

# ── 9. Open in Xcode ──────────────────────────────────────────────────────────
XCODEPROJ=$(find "$INSTALL_DIR" -maxdepth 2 -name "*.xcodeproj" | head -1)
echo ""
if [[ -n "$XCODEPROJ" ]]; then
  log "Setup complete!"
  echo ""
  echo "╔════════════════════════════════════════════════════════╗"
  echo "║  Next steps:                                           ║"
  echo "║  1. Xcode will open now — select your signing team     ║"
  echo "║  2. Press Cmd+R to build & run                         ║"
  echo "║  3. Grant permissions: microphone, accessibility,      ║"
  echo "║     screen recording when prompted                     ║"
  echo "║  4. HeyClicky appears in your menu bar                 ║"
  echo "╚════════════════════════════════════════════════════════╝"
  echo ""
  open "$XCODEPROJ"
else
  warn "Xcode project not found. Open the project manually from $INSTALL_DIR"
fi
