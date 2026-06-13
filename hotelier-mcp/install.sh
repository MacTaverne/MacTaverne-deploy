#!/bin/bash
set -e

echo "=== hotelier-mcp installer ==="

# 1. Install Node dependencies
cd "$(dirname "$0")"
npm install

# 2. Install Playwright's Chromium browser
npx playwright install chromium

# 3. Store credentials
echo ""
echo "Enter your Little Hotelier credentials (stored in ~/.mactaverne/.hotelier-creds, chmod 600):"
read -rp "  Email/username: " LH_USER
read -rsp "  Password: " LH_PASS
echo ""

node -e "
import('./src/credentials.js').then(({ writeCredentials }) => {
  const path = writeCredentials('$LH_USER', '$LH_PASS');
  console.log('Credentials saved to:', path);
});
"

# 4. Show Claude Desktop config snippet
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo ""
echo "=== Add to Claude Desktop config (~/Library/Application Support/Claude/claude_desktop_config.json) ==="
echo ""
cat <<EOF
{
  "mcpServers": {
    "hotelier": {
      "command": "node",
      "args": ["$SCRIPT_DIR/src/index.js"]
    }
  }
}
EOF
echo ""
echo "=== Or add to Bud's MCP config ==="
echo "  command: node $SCRIPT_DIR/src/index.js"
echo ""
echo "Done. Run 'node src/index.js' to start the MCP server manually."
