/* =====================================================================
   Stale — client-side Mac app update checker.
   Matches your installed apps against the Homebrew Cask version database.
   Nothing is uploaded; all matching happens in your browser.

   Architecture (single buildless module, organised into sections):
     1. Config + DOM refs            6. Analysis (grouping + severity)
     2. IndexedDB key/value store    7. Freshness score + diffing
     3. Cask DB loading              8. Rendering
     4. Name normalisation + index   9. Actions (brew, reminder, share)
     5. Version compare             10. PWA + events + boot + debug API
   ===================================================================== */
"use strict";

/* ---------- 1. Config + DOM refs ---------- */
const CASK_URL  = "https://formulae.brew.sh/api/cask.json";
const CACHE_TTL = 12 * 60 * 60 * 1000;            // 12h freshness for the DB cache
const CIRC      = 2 * Math.PI * 52;               // gauge circumference (r=52)

/* Build identity — distinguishes the LOCAL entity (run.command on your Mac) from the
   deployed WEB entity (public URL). Both run the EXACT same engine, so performance is
   identical; only the identity, on-screen label, and storage namespace differ. This is
   why the two never share data or interfere, even though they share one codebase. */
function detectBuild(host, proto, metaVal) {
  const m = metaVal && metaVal !== "auto" ? String(metaVal).toLowerCase() : null;
  if (m === "local" || m === "web") return m;        // explicit <meta> override wins
  const isLocal =
    host === "localhost" || host === "127.0.0.1" || host === "[::1]" || host === "" || proto === "file:";
  return isLocal ? "local" : "web";
}
/* Native entity: when running inside the Stale.app WKWebView, a "staleScan" message
   handler is injected by Swift. That presence (or ?build=app) makes this the APP entity,
   which can scan the Mac directly — no Terminal step. Same engine as Local/Web. */
const IS_NATIVE =
  !!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.staleScan) ||
  new URLSearchParams(location.search).get("build") === "app";
const BUILD = IS_NATIVE
  ? "app"
  : detectBuild(
      location.hostname, location.protocol,
      new URLSearchParams(location.search).get("build") ||     // ?build=web|local override
      (document.querySelector('meta[name="stale-build"]') || {}).content
    );
const DB_NAME = "stale-" + BUILD;                  // namespaced per entity → storage never shared

const $ = (id) => document.getElementById(id);
const dom = {
  window: $("window"), intro: $("intro"), results: $("results"),
  dbStatus: $("dbStatus"), dbText: $("dbText"),
  input: $("input"), checkBtn: $("checkBtn"), sampleBtn: $("sampleBtn"),
  clearBtn: $("clearBtn"), copyCmd: $("copyCmd"),
  resume: $("resume"), resumeMeta: $("resumeMeta"), resumeBtn: $("resumeBtn"),
  gaugeFill: $("gaugeFill"), gaugeScore: $("gaugeScore"),
  scoreHeadline: $("scoreHeadline"), scoreSub: $("scoreSub"), diff: $("diff"),
  summary: $("summary"), search: $("search"), groups: $("groups"),
  disclaimer: $("disclaimer"), rescanBtn: $("rescanBtn"), remindBtn: $("remindBtn"),
  installBtn: $("installBtn"), toast: $("toast"), buildBadge: $("buildBadge"),
};

/* mutable app state */
const state = {
  casks: null,        // raw cask array
  index: null,        // Map<normalizedName, cask>
  lastScan: null,     // {ts, apps:[{name,file,version,source}], score}
  groups: null,       // current rendered grouping
  deferredPrompt: null,
};

/* ---------- 2. IndexedDB key/value store ---------- */
function idb(mode, fn) {
  return new Promise((resolve, reject) => {
    let open;
    try { open = indexedDB.open(DB_NAME, 1); }
    catch (e) { return reject(e); }
    open.onupgradeneeded = () => open.result.createObjectStore("kv");
    open.onerror = () => reject(open.error);
    open.onsuccess = () => {
      const db = open.result;
      const tx = db.transaction("kv", mode);
      const store = tx.objectStore("kv");
      const req = fn(store);
      tx.oncomplete = () => resolve(req && req.result);
      tx.onerror = () => reject(tx.error);
      tx.onabort = () => reject(tx.error);
    };
  });
}
const kvGet = (k) => idb("readonly",  (s) => s.get(k)).catch(() => null);
const kvSet = (k, v) => idb("readwrite", (s) => s.put(v, k)).catch(() => {});

/* ---------- 3. Cask DB loading (cache-first, refresh, offline fallback) ---------- */
async function loadCasks() {
  setDb("loading", "loading database…");
  let cached = null;
  try { cached = await kvGet("casks"); } catch {}

  if (cached && cached.data && (Date.now() - cached.ts) < CACHE_TTL) {
    apply(cached.data, "cached");
    return;
  }
  try {
    const res = await fetch(CASK_URL, { cache: "no-store" });
    if (!res.ok) throw new Error("HTTP " + res.status);
    const data = await res.json();
    if (!Array.isArray(data) || !data.length) throw new Error("unexpected payload");
    apply(data, "fresh");
    kvSet("casks", { data, ts: Date.now() });
  } catch (err) {
    if (cached && cached.data) {                 // network down → use stale copy
      apply(cached.data, "offline");
    } else {
      setDb("error", "couldn’t load database");
      toast("Couldn’t reach the Homebrew database. Check your connection and reload.");
    }
  }

  function apply(data, mode) {
    state.casks = data;
    state.index = buildIndex(data);
    const label = { cached: " (cached)", offline: " (offline copy)", fresh: "" }[mode] || "";
    setDb("ready", fmtNum(data.length) + " apps tracked" + label);
    dom.checkBtn.disabled = dom.input.value.trim().length === 0;
  }
}
function setDb(stateName, text) {
  dom.dbStatus.className = "db" + (stateName === "ready" ? " ready" : stateName === "error" ? " error" : "");
  dom.dbText.textContent = text;
}

/* ---------- 4. Name normalisation + index ---------- */
function norm(s) {
  return String(s || "")
    .replace(/\.app$/i, "")
    .replace(/[™®©℠]/g, "")              // strip BEFORE NFKD, else ™ decomposes to "TM"
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "")     // drop combining marks (café -> cafe)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "")
    .trim();
}
function buildIndex(casks) {
  const idx = new Map();
  const add = (key, cask) => {
    const k = norm(key);
    if (!k) return;
    const cur = idx.get(k);
    // prefer non-deprecated / non-disabled on collision
    if (!cur || ((cur.deprecated || cur.disabled) && !(cask.deprecated || cask.disabled))) idx.set(k, cask);
  };
  for (const cask of casks) {
    for (const art of (cask.artifacts || [])) {
      if (Array.isArray(art)) {                                  // ["Foo.app"]
        for (const a of art) if (typeof a === "string" && /\.app$/i.test(a)) add(a, cask);
      } else if (art && typeof art === "object" && Array.isArray(art.app)) {
        for (const a of art.app) if (typeof a === "string") add(a, cask);
      }
    }
    for (const n of (cask.name || [])) add(n, cask);
    add(cask.token, cask);
  }
  return idx;
}

/* ---------- 5. Version compare (heuristic) ---------- */
function verParts(v) {
  if (v == null) return [];
  const head = String(v).split(",")[0].trim();          // cask "1.2,345" -> "1.2"
  return head.split(/[^0-9]+/).filter((x) => x.length).map(Number).filter((n) => !Number.isNaN(n));
}
// 1 (a>b) | -1 (a<b) | 0 (equal) | null (undecidable)
function cmpVer(a, b) {
  const pa = verParts(a), pb = verParts(b);
  if (!pa.length || !pb.length) return null;
  const len = Math.max(pa.length, pb.length);
  for (let i = 0; i < len; i++) {
    const x = pa[i] ?? 0, y = pb[i] ?? 0;
    if (x > y) return 1;
    if (x < y) return -1;
  }
  return 0;
}
// how far behind: installed vs latest
function severity(installed, latest) {
  const a = verParts(installed), b = verParts(latest);
  if (!a.length || !b.length) return "unknown";
  if ((b[0] ?? 0) > (a[0] ?? 0)) return "major";
  if ((b[0] ?? 0) === (a[0] ?? 0) && (b[1] ?? 0) > (a[1] ?? 0)) return "minor";
  return "patch";
}

/* ---------- 6. Input parsing + analysis ---------- */
function parseInput(raw) {
  raw = (raw || "").trim();
  if (!raw) return { apps: [], error: null };
  let json;
  try { json = JSON.parse(raw); }
  catch { return { apps: [], error: "That doesn’t look like the command output. Re-run Step 1 and paste the whole thing." }; }

  let arr = json.SPApplicationsDataType;
  if (!Array.isArray(arr) && Array.isArray(json)) arr = json;        // tolerate a bare array
  if (!Array.isArray(arr)) return { apps: [], error: "Couldn’t find the app list in that JSON. Use the exact command above." };

  const apps = [];
  for (const a of arr) {
    const name = a && a._name;
    if (!name) continue;
    const path = a.path || "";
    const file = (path.split("/").pop() || (name + ".app"));
    apps.push({ name, file, version: a.version || null, source: a.obtained_from || "unknown", path });
  }
  return { apps: dedupe(apps), error: null };
}
// real exports contain duplicates (e.g. two "Epic Games Launcher"); keep the best
function dedupe(apps) {
  const by = new Map();
  for (const app of apps) {
    const key = norm(app.file) || norm(app.name);
    const cur = by.get(key);
    if (!cur) { by.set(key, app); continue; }
    // prefer the entry that has a version, then the higher version
    if (!cur.version && app.version) by.set(key, app);
    else if (cur.version && app.version && cmpVer(app.version, cur.version) === 1) by.set(key, app);
  }
  return [...by.values()];
}

function analyze(apps) {
  const groups = { action: [], self: [], ok: [], unknown: [], mas: [] };
  for (const app of apps) {
    if (app.source === "apple") continue;                       // Apple's bundled apps update via macOS
    if (app.source === "mac_app_store") { groups.mas.push({ app, cask: null, status: "mas" }); continue; }

    const cask = state.index.get(norm(app.file)) || state.index.get(norm(app.name));
    if (!cask) { groups.unknown.push({ app, cask: null, status: "unknown" }); continue; }

    if (!app.version) { groups.ok.push({ app, cask, status: "noversion" }); continue; }

    const cmp = cmpVer(cask.version, app.version);              // latest vs installed
    if (cmp === 1) {
      const entry = { app, cask, status: "outdated", latest: cask.version, severity: severity(app.version, cask.version) };
      (cask.auto_updates ? groups.self : groups.action).push(entry);
    } else if (cmp === 0) {
      groups.ok.push({ app, cask, status: "current" });
    } else if (cmp === -1) {
      groups.ok.push({ app, cask, status: "ahead" });          // on a newer/beta build
    } else {
      const entry = { app, cask, status: "differs", latest: cask.version, severity: "unknown" };
      (cask.auto_updates ? groups.self : groups.action).push(entry);
    }
  }
  const byName = (a, b) => a.app.name.localeCompare(b.app.name);
  const sevRank = { major: 0, minor: 1, patch: 2, unknown: 3 };
  groups.action.sort((a, b) => (sevRank[a.severity] - sevRank[b.severity]) || byName(a, b));
  groups.self.sort(byName); groups.ok.sort(byName); groups.unknown.sort(byName); groups.mas.sort(byName);
  return groups;
}

/* ---------- 7. Freshness score + diffing ---------- */
function freshnessWeight(e) {
  if (e.status === "current" || e.status === "ahead") return 1;
  if (e.status === "differs") return 0.7;
  const base = { major: 0.2, minor: 0.5, patch: 0.8, unknown: 0.6 }[e.severity || "unknown"];
  return e.cask && e.cask.auto_updates ? Math.min(1, base + 0.3) : base;   // self-updaters cushioned
}
function freshnessScore(groups) {
  const matched = [...groups.action, ...groups.self, ...groups.ok].filter((e) => e.status !== "noversion");
  if (!matched.length) return null;
  const sum = matched.reduce((acc, e) => acc + freshnessWeight(e), 0);
  return Math.round((100 * sum) / matched.length);
}
function diffSince(apps, prev) {
  if (!prev || !prev.apps) return null;
  const prevMap = new Map(prev.apps.map((a) => [norm(a.file) || norm(a.name), a.version]));
  let updated = 0, added = 0;
  for (const a of apps) {
    const key = norm(a.file) || norm(a.name);
    if (!prevMap.has(key)) added++;
    else if (a.version && prevMap.get(key) && cmpVer(a.version, prevMap.get(key)) === 1) updated++;
  }
  return { updated, added, when: prev.ts };
}

/* ---------- 8. Rendering ---------- */
const AVATAR_COLORS = ["#0a84ff","#28b463","#ff9f0a","#ff375f","#bf5af2","#5e5ce6","#0fb5c4","#e0a900","#ff6482","#30b0c7"];
function avatarColor(name) { let h = 0; for (const c of name) h = (h * 31 + c.charCodeAt(0)) >>> 0; return AVATAR_COLORS[h % AVATAR_COLORS.length]; }
function esc(s) { return String(s).replace(/[&<>"']/g, (c) => ({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;" }[c])); }
function fmtNum(n) { return Number(n).toLocaleString("en-US"); }
function fmtDate(ts) { try { return new Date(ts).toLocaleDateString(undefined, { month: "short", day: "numeric" }); } catch { return ""; } }

function gaugeColor(score) {
  if (score >= 80) return getCSS("--green");
  if (score >= 50) return getCSS("--amber");
  return getCSS("--red");
}
function getCSS(v) { return getComputedStyle(document.documentElement).getPropertyValue(v).trim(); }

function setGauge(score) {
  if (score == null) {
    dom.gaugeScore.textContent = "—";
    dom.gaugeFill.style.strokeDashoffset = CIRC;
    return;
  }
  dom.gaugeFill.style.stroke = gaugeColor(score);
  dom.gaugeFill.style.strokeDashoffset = CIRC * (1 - score / 100);
  animateNumber(dom.gaugeScore, score);
}
function animateNumber(el, to) {
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  if (reduce) { el.textContent = to; return; }
  const start = performance.now(), dur = 900, from = 0;
  function tick(now) {
    const t = Math.min(1, (now - start) / dur);
    const eased = 1 - Math.pow(1 - t, 3);
    el.textContent = Math.round(from + (to - from) * eased);
    if (t < 1) requestAnimationFrame(tick);
  }
  requestAnimationFrame(tick);
}

function scoreHeadline(score, groups) {
  if (score == null) return { h: "No third-party apps to check", s: "Everything in your list is an Apple or App Store app — those update on their own." };
  const need = groups.action.length;
  if (score >= 90) return { h: "Your Mac is fresh 🍃", s: need ? `${need} app${need>1?"s":""} could still use a look.` : "Nothing needs your attention right now." };
  if (score >= 70) return { h: "Looking good", s: `${need} app${need===1?"":"s"} worth updating when you get a moment.` };
  if (score >= 50) return { h: "A few things are aging", s: `${need} app${need===1?"":"s"} are behind — worth a refresh.` };
  return { h: "Time for a refresh", s: `${need} app${need===1?"":"s"} are noticeably out of date.` };
}

function appRow(entry) {
  const { app, cask, status, latest, severity: sev } = entry;
  const color = avatarColor(app.name);
  const letter = (app.name.match(/[A-Za-z0-9]/) || ["?"])[0].toUpperCase();
  let ver;
  if (status === "outdated" || status === "differs") {
    const sevTag = (status === "outdated" && sev && sev !== "unknown") ? `<span class="sev ${sev}">${sev}</span>` : "";
    ver = `<div class="ver"><span class="old">${esc(app.version || "?")}</span><span class="arrow">→</span><span class="new">${esc(latest)}</span>${sevTag}${status==="differs"?'<span class="tag">version differs</span>':""}</div>`;
  } else if (status === "current") {
    ver = `<div class="ver same"><span class="cur">✓ ${esc(app.version || "")}</span> · up to date</div>`;
  } else if (status === "ahead") {
    ver = `<div class="ver same"><span class="cur">${esc(app.version || "")}</span> · ahead of release (${esc(cask.version)})</div>`;
  } else if (status === "noversion") {
    ver = `<div class="ver">version unknown · matched ${esc(cask.token)}</div>`;
  } else if (status === "mas") {
    ver = `<div class="ver">${esc(app.version || "")} · updates in the App Store</div>`;
  } else {
    ver = `<div class="ver">${esc(app.version || "version unknown")}</div>`;
  }
  const right = [];
  if (cask) {
    if (cask.auto_updates && (status === "outdated" || status === "differs"))
      right.push(`<span class="tag" title="This app updates itself — usually no action needed">self-updates</span>`);
    if (status === "outdated" || status === "differs")
      right.push(`<span class="pill" data-copy="brew install --cask ${esc(cask.token)}" title="Copy Homebrew command">brew ⧉</span>`);
    if (cask.homepage)
      right.push(`<a class="open" href="${esc(cask.homepage)}" target="_blank" rel="noopener noreferrer" title="Open ${esc(cask.name?.[0]||"homepage")}">↗</a>`);
  }
  return `<div class="app" data-name="${esc((app.name||"").toLowerCase())}">
    <div class="avatar" style="background:${color}" aria-hidden="true">${esc(letter)}</div>
    <div class="meta"><div class="name">${esc(app.name)}</div>${ver}</div>
    <div class="right">${right.join("")}</div>
  </div>`;
}

function groupBlock(cls, dot, title, items, open, footer) {
  if (!items.length) return "";
  return `<details class="group ${cls}" ${open ? "open" : ""}>
    <summary><span class="dot" aria-hidden="true">${dot}</span> ${title} <span class="badge">${items.length}</span><span class="chev" aria-hidden="true">▶</span></summary>
    <div class="applist">${items.map(appRow).join("")}</div>
    ${footer || ""}
  </details>`;
}

function render(groups, diff) {
  state.groups = groups;
  const score = freshnessScore(groups);

  // scoreboard
  setGauge(score);
  const head = scoreHeadline(score, groups);
  dom.scoreHeadline.textContent = head.h;
  dom.scoreSub.textContent = head.s;

  // diff banner
  if (diff && (diff.updated || diff.added)) {
    const bits = [];
    if (diff.updated) bits.push(`<span class="pill-diff up">↑ ${diff.updated} updated since ${fmtDate(diff.when)}</span>`);
    if (diff.added) bits.push(`<span class="pill-diff new">＋ ${diff.added} new app${diff.added>1?"s":""}</span>`);
    dom.diff.innerHTML = bits.join("");
    dom.diff.hidden = false;
  } else dom.diff.hidden = true;

  // summary chips
  dom.summary.innerHTML = `
    <button class="sumcard act" data-jump="action"><div class="n">${groups.action.length}</div><div class="l">Worth updating</div></button>
    <button class="sumcard ok" data-jump="ok"><div class="n">${groups.ok.length}</div><div class="l">Up to date</div></button>
    <button class="sumcard" data-jump="self"><div class="n">${groups.self.length}</div><div class="l">Self-updating</div></button>
    <button class="sumcard" data-jump="unknown"><div class="n">${groups.unknown.length}</div><div class="l">Not tracked</div></button>`;

  // batch action footer for the action group
  const tokens = groups.action.filter((e) => e.cask && e.cask.token).map((e) => e.cask.token);
  const actionFooter = tokens.length
    ? `<div class="group-actions"><button class="btn small ghost" data-batch="${esc(tokens.join(" "))}">⧉ Copy update commands (${tokens.length})</button></div>`
    : "";

  dom.groups.innerHTML =
    groupBlock("action", "🍂", "Worth updating", groups.action, true, actionFooter) +
    groupBlock("self", "🔄", "Newer version exists — but these update themselves", groups.self, false) +
    groupBlock("ok", "✅", "Up to date", groups.ok, false) +
    groupBlock("unknown", "❓", "Not in Homebrew’s database", groups.unknown, false) +
    groupBlock("mas", "🛍️", "Mac App Store — manage updates there", groups.mas, false);

  const total = Object.values(groups).reduce((n, g) => n + g.length, 0);
  if (total === 0) dom.groups.innerHTML = `<div class="empty">No apps found in that list. Did the command finish copying before you pasted?</div>`;

  dom.disclaimer.innerHTML =
    `Stale compares your versions against <strong>${fmtNum(state.casks.length)}</strong> apps in the Homebrew Cask database. ` +
    `Matching is by app name and version comparison is a best-effort heuristic — <strong>always confirm before updating</strong>, ` +
    `and prefer each app’s own “Check for Updates” or your package manager. Apps not in the database simply aren’t tracked by Homebrew; that doesn’t mean they’re out of date.`;

  dom.intro.hidden = true;
  dom.results.hidden = false;
  dom.results.scrollIntoView({ behavior: "smooth", block: "start" });
}

/* ---------- 9. Actions ---------- */
function runCheck(apps, { diff = true } = {}) {
  if (!state.index) { toast("Database is still loading — one moment."); return false; }
  if (!apps.length) { toast("No apps found in that text."); return false; }
  const d = diff ? diffSince(apps, state.lastScan) : null;
  const groups = analyze(apps);
  render(groups, d);
  // persist as the new "last scan"
  state.lastScan = { ts: Date.now(), apps: apps.map(({ name, file, version, source }) => ({ name, file, version, source })), score: freshnessScore(groups) };
  kvSet("lastScan", state.lastScan);
  dom.clearBtn.hidden = false;
  return true;
}

function copyText(text, msg) {
  const done = () => toast(msg);
  if (navigator.clipboard && navigator.clipboard.writeText) {
    navigator.clipboard.writeText(text).then(done).catch(() => fallbackCopy(text, done));
  } else fallbackCopy(text, done);
}
function fallbackCopy(text, done) {
  const ta = document.createElement("textarea");
  ta.value = text; ta.style.position = "fixed"; ta.style.opacity = "0";
  document.body.appendChild(ta); ta.focus(); ta.select();
  try { document.execCommand("copy"); done(); } catch {}
  ta.remove();
}

function buildICS() {
  const now = new Date();
  const start = new Date(now.getTime() + 14 * 86400000);
  const pad = (n) => String(n).padStart(2, "0");
  const fmt = (d) => `${d.getUTCFullYear()}${pad(d.getUTCMonth()+1)}${pad(d.getUTCDate())}T${pad(d.getUTCHours())}${pad(d.getUTCMinutes())}00Z`;
  const uid = "stale-" + now.getTime() + "@stale.local";
  return [
    "BEGIN:VCALENDAR","VERSION:2.0","PRODID:-//Stale//Mac App Checker//EN","CALSCALE:GREGORIAN","BEGIN:VEVENT",
    "UID:" + uid, "DTSTAMP:" + fmt(now), "DTSTART:" + fmt(start), "DURATION:PT15M",
    "SUMMARY:🍂 Check your Mac apps with Stale", "DESCRIPTION:Open Stale and run a fresh scan to see which apps have gone stale.",
    "BEGIN:VALARM","TRIGGER:-PT0M","ACTION:DISPLAY","DESCRIPTION:Time to check your Mac apps","END:VALARM",
    "END:VEVENT","END:VCALENDAR",
  ].join("\r\n");
}
function downloadReminder() {
  const blob = new Blob([buildICS()], { type: "text/calendar" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url; a.download = "stale-reminder.ics";
  document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
  toast("Reminder saved — opens in your calendar (2 weeks out)");
}

/* filter */
function applyFilter(q) {
  q = q.trim().toLowerCase();
  document.querySelectorAll(".group").forEach((g) => {
    let shown = 0;
    g.querySelectorAll(".app").forEach((a) => {
      const match = !q || (a.dataset.name || "").includes(q);
      a.style.display = match ? "" : "none";
      if (match) shown++;
    });
    g.style.display = shown || !q ? "" : "none";
    if (q && shown) g.open = true;
  });
}

/* ---------- 10. PWA + events + boot + debug ---------- */
function registerSW() {
  if (!("serviceWorker" in navigator)) return;
  if (location.protocol === "file:") return;
  navigator.serviceWorker.register("service-worker.js").catch(() => {});
}
function setupInstall() {
  if (IS_NATIVE) return;                         // already a real app; no "Add to Dock"
  const standalone = matchMedia("(display-mode: standalone)").matches || navigator.standalone;
  if (standalone) return;
  dom.installBtn.hidden = false;
  window.addEventListener("beforeinstallprompt", (e) => { e.preventDefault(); state.deferredPrompt = e; });
  dom.installBtn.addEventListener("click", async () => {
    if (state.deferredPrompt) {
      state.deferredPrompt.prompt();
      await state.deferredPrompt.userChoice.catch(() => {});
      state.deferredPrompt = null;
    } else {
      toast("In Safari: File → Add to Dock. In Chrome: ⋮ → Install. It’ll live in your Dock.");
    }
  });
}

function wireEvents() {
  dom.copyCmd.addEventListener("click", () => {
    copyText("system_profiler SPApplicationsDataType -json | pbcopy", "Command copied — paste it into Terminal");
    dom.copyCmd.textContent = "Copied!"; dom.copyCmd.classList.add("done");
    setTimeout(() => { dom.copyCmd.textContent = "Copy"; dom.copyCmd.classList.remove("done"); }, 1500);
  });
  dom.input.addEventListener("input", () => { dom.checkBtn.disabled = !dom.input.value.trim() || !state.index; });
  dom.checkBtn.addEventListener("click", () => {
    const { apps, error } = parseInput(dom.input.value);
    if (error) return toast(error);
    runCheck(apps);
  });
  dom.clearBtn.addEventListener("click", resetToIntro);
  dom.rescanBtn.addEventListener("click", resetToIntro);
  dom.remindBtn.addEventListener("click", downloadReminder);
  dom.search.addEventListener("input", (e) => applyFilter(e.target.value));

  // delegated clicks inside results: brew pill, batch copy, summary jump
  dom.results.addEventListener("click", (e) => {
    const pill = e.target.closest(".pill[data-copy]");
    if (pill) return copyText(pill.dataset.copy, "Copied: " + pill.dataset.copy);
    const batch = e.target.closest("[data-batch]");
    if (batch) {
      const tokens = batch.dataset.batch.split(" ").filter(Boolean);
      const cmd = "# Update with Homebrew (installs the latest cask):\nbrew install --cask " + tokens.join(" ");
      return copyText(cmd, `Copied a brew command for ${tokens.length} app${tokens.length>1?"s":""}`);
    }
    const jump = e.target.closest("[data-jump]");
    if (jump) {
      const g = dom.groups.querySelector(".group." + jump.dataset.jump);
      if (g) { g.open = true; g.scrollIntoView({ behavior: "smooth", block: "center" }); }
    }
  });

  // drag & drop a .json file onto the textarea
  ["dragenter", "dragover"].forEach((ev) => dom.input.addEventListener(ev, (e) => { e.preventDefault(); dom.input.classList.add("dragover"); }));
  ["dragleave", "drop"].forEach((ev) => dom.input.addEventListener(ev, () => dom.input.classList.remove("dragover")));
  dom.input.addEventListener("drop", (e) => {
    e.preventDefault();
    const file = e.dataTransfer.files[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = () => {
      dom.input.value = reader.result;
      dom.checkBtn.disabled = !state.index;
      const { apps, error } = parseInput(dom.input.value);
      if (error) return toast(error);
      runCheck(apps);
    };
    reader.readAsText(file);
  });

  // sample data
  dom.sampleBtn.addEventListener("click", () => {
    dom.input.value = JSON.stringify(SAMPLE, null, 2);
    dom.checkBtn.disabled = !state.index;
    if (!state.index) return toast("Database still loading — try again in a second.");
    const { apps } = parseInput(dom.input.value);
    runCheck(apps);
  });

  // resume last scan
  dom.resumeBtn.addEventListener("click", () => {
    if (!state.lastScan) return;
    if (!state.index) return toast("Database still loading — one moment.");
    runCheck(state.lastScan.apps, { diff: false });
  });
}

function resetToIntro() {
  dom.input.value = ""; dom.checkBtn.disabled = true;
  dom.results.hidden = true; dom.intro.hidden = false; dom.clearBtn.hidden = true;
  dom.search.value = "";
  window.scrollTo({ top: 0, behavior: "smooth" });
}

let toastTimer;
function toast(msg) {
  dom.toast.textContent = msg; dom.toast.classList.add("show");
  clearTimeout(toastTimer); toastTimer = setTimeout(() => dom.toast.classList.remove("show"), 2200);
}

async function showResumeIfAny() {
  try { state.lastScan = await kvGet("lastScan"); } catch {}
  if (state.lastScan && state.lastScan.apps && state.lastScan.apps.length) {
    const s = state.lastScan;
    dom.resumeMeta.textContent = ` Last scan ${fmtDate(s.ts)} · ${s.apps.length} apps` + (s.score != null ? ` · freshness ${s.score}` : "");
    dom.resume.hidden = false;
  }
}

/* sample data (lets people try without Terminal; also drives tests) */
const SAMPLE = { SPApplicationsDataType: [
  { _name: "Visual Studio Code", version: "1.85.0", path: "/Applications/Visual Studio Code.app", obtained_from: "identified_developer" },
  { _name: "Google Chrome", version: "120.0.6099.109", path: "/Applications/Google Chrome.app", obtained_from: "identified_developer" },
  { _name: "Rectangle", version: "0.70", path: "/Applications/Rectangle.app", obtained_from: "identified_developer" },
  { _name: "VLC", version: "3.0.16", path: "/Applications/VLC.app", obtained_from: "identified_developer" },
  { _name: "HandBrake", version: "1.5.1", path: "/Applications/HandBrake.app", obtained_from: "identified_developer" },
  { _name: "Transmission", version: "4.0.4", path: "/Applications/Transmission.app", obtained_from: "identified_developer" },
  { _name: "IINA", version: "1.3.0", path: "/Applications/IINA.app", obtained_from: "identified_developer" },
  { _name: "Calibre", version: "6.20.0", path: "/Applications/calibre.app", obtained_from: "identified_developer" },
  { _name: "1Password", version: "8.10.0", path: "/Applications/1Password.app", obtained_from: "identified_developer" },
  { _name: "Spotify", version: "1.2.20.1216", path: "/Applications/Spotify.app", obtained_from: "identified_developer" },
  { _name: "Figma", version: "124.0.0", path: "/Applications/Figma.app", obtained_from: "identified_developer" },
  { _name: "Things3", version: "3.19.0", path: "/Applications/Things3.app", obtained_from: "mac_app_store" },
  { _name: "AcmeCorp Internal Tool", version: "1.0.2", path: "/Applications/AcmeCorp Internal Tool.app", obtained_from: "identified_developer" },
  { _name: "Safari", version: "17.2", path: "/Applications/Safari.app", obtained_from: "apple" },
] };

/* show which entity this is (Local / Web / App) */
function applyBuildIdentity() {
  document.documentElement.setAttribute("data-build", BUILD);
  const badge = dom.buildBadge;
  if (!badge) return;
  const labels = {
    app:   ["App",   "The native Mac app. Scans your Mac directly — no Terminal needed."],
    local: ["Local", "Running locally on your Mac. Separate storage from the web version."],
    web:   ["Web",   "The public web version. Separate storage from your local instance."],
  };
  const [text, title] = labels[BUILD] || labels.web;
  badge.textContent = text;
  badge.title = title;
  badge.hidden = false;
}

/* ---------- Native bridge (only active inside Stale.app) ---------- */
// Swift calls window.__staleReceiveScan(jsonString) with system_profiler output.
function setupNative() {
  if (!IS_NATIVE) return;
  document.documentElement.setAttribute("data-native", "true");

  // entry point Swift invokes after running system_profiler
  window.__staleReceiveScan = (json) => {
    try {
      const { apps, error } = parseInput(typeof json === "string" ? json : JSON.stringify(json));
      if (error) { toast(error); return; }
      if (!state.index) {                       // DB not ready yet → retry shortly
        let tries = 0;
        const wait = setInterval(() => {
          if (state.index) { clearInterval(wait); runCheck(apps); }
          else if (++tries > 60) { clearInterval(wait); toast("Database didn’t load — check your connection."); }
        }, 200);
        return;
      }
      runCheck(apps);
    } catch (e) { toast("Couldn’t read the scan results."); }
  };

  // ask Swift to scan
  window.__staleRequestScan = () => {
    try { window.webkit.messageHandlers.staleScan.postMessage("scan"); toast("Scanning your Mac…"); }
    catch { toast("Native scan unavailable."); }
  };

  // wire the native scan button (revealed by CSS in native mode)
  const btn = $("scanBtn");
  if (btn) btn.addEventListener("click", () => window.__staleRequestScan());
}

/* boot */
function boot() {
  // one-time cleanup: pre-1.1 builds used a single un-namespaced DB; drop the orphan.
  try { indexedDB.deleteDatabase("stale-db"); } catch {}
  applyBuildIdentity();
  setupNative();
  wireEvents();
  setupInstall();
  registerSW();
  loadCasks();
  showResumeIfAny();
  // In the native app, kick off a scan automatically once the DB is ready.
  if (IS_NATIVE) {
    let tries = 0;
    const t = setInterval(() => {
      if (state.index) { clearInterval(t); window.__staleRequestScan && window.__staleRequestScan(); }
      else if (++tries > 80) clearInterval(t);
    }, 150);
  }
}
boot();

/* debug/test API (used by the pilot test-suite; harmless in production) */
window.Stale = {
  state, norm, verParts, cmpVer, severity, parseInput, dedupe, analyze,
  freshnessScore, freshnessWeight, diffSince, runCheck, buildICS, SAMPLE,
  build: BUILD, dbName: DB_NAME, detectBuild, isNative: IS_NATIVE,
};
