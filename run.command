#!/bin/bash
# =====================================================================
#  Stale — local launcher
#  Double-click this file to run Stale on your Mac. It starts a tiny
#  local web server and opens Stale in your default browser.
#  Nothing leaves your machine. Close this window (or press Ctrl-C) to stop.
# =====================================================================

# Always run from the folder this script lives in (so it serves the app).
cd "$(dirname "$0")" || exit 1

# Pick a Python (3 preferred).
if command -v python3 >/dev/null 2>&1; then
  PY=python3
elif command -v python >/dev/null 2>&1; then
  PY=python
else
  echo ""
  echo "  ⚠️  Python isn't installed, so the launcher can't start a server."
  echo "      Easiest fix: install Homebrew (https://brew.sh) then run: brew install python"
  echo "      Or just open index.html in your browser (note: offline/Dock features need a server)."
  echo ""
  read -r -p "  Press Return to close…" _
  exit 1
fi

# Find a free port, starting at 8765.
PORT=8765
while lsof -i ":$PORT" >/dev/null 2>&1; do
  PORT=$((PORT + 1))
done

URL="http://localhost:$PORT"

echo ""
echo "  🍂  Stale is running locally"
echo "  ────────────────────────────────────────────────"
echo "     Open in your browser:   $URL"
echo "     Serving folder:         $(pwd)"
echo ""
echo "     • Keep this window open while you use Stale."
echo "     • To stop:  close this window, or press Ctrl-C."
echo "  ────────────────────────────────────────────────"
echo ""

# Open the browser a moment after the server is up.
( sleep 1; open "$URL" >/dev/null 2>&1 ) &

# Serve the current folder. exec so Ctrl-C / window-close stops the server cleanly.
exec "$PY" -m http.server "$PORT"
