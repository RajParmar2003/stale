#!/bin/bash
# =====================================================================
#  compare.sh — render the current UI next to a past commit, side by side.
#
#  Serves the working tree (AFTER) and a chosen commit (BEFORE) on two local
#  ports, then opens a comparison page with both in iframes. Useful for a
#  visual before/after of any redesign.
#
#  Usage:
#    ./scripts/compare.sh                 # BEFORE = the initial commit
#    ./scripts/compare.sh <commit-ish>    # BEFORE = any commit / tag / branch
#
#  Press Ctrl-C to stop; it cleans up the servers, worktree, and temp page.
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")/.."                    # repo root

BEFORE_REF="${1:-$(git rev-list --max-parents=0 HEAD | tail -1)}"   # default: first commit
AFTER_PORT=4396
BEFORE_PORT=4397
PAGE_PORT=4398
WORKTREE="$(mktemp -d)/stale-before"
PAGE_DIR="$(mktemp -d)"

cleanup() {
  echo ""; echo "cleaning up…"
  kill "${PIDS[@]}" 2>/dev/null || true
  git worktree remove "$WORKTREE" --force 2>/dev/null || true
  rm -rf "$PAGE_DIR" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "BEFORE = $BEFORE_REF"
echo "AFTER  = working tree ($(git branch --show-current 2>/dev/null || echo detached))"

git worktree add -q --detach "$WORKTREE" "$BEFORE_REF"

PIDS=()
( cd .          && python3 -m http.server "$AFTER_PORT"  >/dev/null 2>&1 ) & PIDS+=($!)
( cd "$WORKTREE" && python3 -m http.server "$BEFORE_PORT" >/dev/null 2>&1 ) & PIDS+=($!)

cat > "$PAGE_DIR/index.html" <<HTML
<!DOCTYPE html><html><head><meta charset="utf-8"><title>Stale — before & after</title><style>
  *{margin:0;box-sizing:border-box}
  body{background:#0a0a0c;font-family:-apple-system,system-ui,sans-serif;padding:22px}
  h1{color:#f4f4f6;font-size:15px;font-weight:600;margin-bottom:16px;text-align:center;letter-spacing:-.01em}
  .row{display:flex;gap:22px}.col{flex:1}
  .label{display:flex;align-items:center;gap:8px;margin:0 2px 10px;font-size:13px;font-weight:700;letter-spacing:.04em;text-transform:uppercase}
  .before .label{color:#ff8a7a}.after .label{color:#5ee08e}
  .tag{font-size:10px;font-weight:600;padding:2px 8px;border-radius:99px}
  .before .tag{background:rgba(255,138,122,.15);color:#ff8a7a}.after .tag{background:rgba(94,224,142,.15);color:#5ee08e}
  .frame{width:100%;height:560px;border:1px solid #26262e;border-radius:12px;overflow:hidden;background:#000}
  iframe{width:166%;height:930px;border:0;transform:scale(.6);transform-origin:top left}
  .cap{color:#8a8a93;font-size:11px;margin-top:8px;line-height:1.5;padding:0 2px}
</style></head><body>
  <h1>Stale — before &amp; after</h1>
  <div class="row">
    <div class="col before"><div class="label">Before <span class="tag">$BEFORE_REF</span></div>
      <div class="frame"><iframe src="http://localhost:$BEFORE_PORT/index.html?nosw"></iframe></div>
      <div class="cap">earlier commit</div></div>
    <div class="col after"><div class="label">After <span class="tag">current</span></div>
      <div class="frame"><iframe src="http://localhost:$AFTER_PORT/index.html?nosw"></iframe></div>
      <div class="cap">working tree</div></div>
  </div>
</body></html>
HTML
( cd "$PAGE_DIR" && python3 -m http.server "$PAGE_PORT" >/dev/null 2>&1 ) & PIDS+=($!)

sleep 1
URL="http://localhost:$PAGE_PORT/"
echo ""; echo "  Comparison ready → $URL"
echo "  (Ctrl-C to stop)"
open "$URL" 2>/dev/null || true
wait
