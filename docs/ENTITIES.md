# Two Entities: Local vs Web

> How Stale runs as **two separate, independent entities** that nonetheless behave and
> perform identically. Last updated: 2026-05-29 (v1.1).

## TL;DR

There are two ways to run Stale, and they are **genuinely separate entities** — separate
identity, separate storage, separate offline cache, separate origin — yet they share **one
engine**, so they do the same things at the same speed.

| | **Local entity** | **Web entity** |
|---|---|---|
| How it runs | `run.command` on your Mac (`http://localhost:8765`) | Deployed to a public URL |
| Badge in the UI | amber **LOCAL** | blue **WEB** |
| `window.Stale.build` | `"local"` | `"web"` |
| IndexedDB name | `stale-local` | `stale-web` |
| Service-worker cache | `stale-shell-local-v1` | `stale-shell-web-v1` |
| Browser origin | `localhost:8765` | e.g. `https://stale.example.com` |
| Engine / features / speed | **identical** | **identical** |

## Why they're truly separate (not the same thing twice)

1. **Different origin → automatic, OS-enforced isolation.** Browsers scope all storage
   (IndexedDB, Cache Storage, service workers) by *origin* = scheme + host + port. The local
   entity (`localhost:8765`) and the web entity (a public domain) are different origins, so the
   browser keeps their data in completely separate sandboxes. One literally cannot read the
   other's data.

2. **Namespaced storage on top of that.** Even within an origin, each entity uses its own
   database (`stale-local` vs `stale-web`) and its own cache bucket. Belt-and-suspenders: they
   stay independent even in the unlikely case they were ever served from the same origin.

3. **Self-identifying.** Each instance detects which entity it is at runtime and shows a badge,
   so there's never any doubt which one you're looking at.

This was **verified** (see `TESTING.md`): writing `"I am LOCAL data"` to `stale-local` and
`"I am WEB data"` to `stale-web`, each entity reads back only its own value — no crossover.

## Why they still perform identically

Both entities load the **same** `index.html`, `assets/css/styles.css`, and `assets/js/app.js`.
The only thing that differs is a single `BUILD` value computed at startup, which changes the
label and the storage namespace — nothing on the hot path (DB matching, version compare,
scoring, rendering). Same code → same performance.

## How the identity is decided

`detectBuild(hostname, protocol, override)` in `app.js`, in priority order:

1. **Explicit override** — `?build=web` / `?build=local` in the URL, or
   `<meta name="stale-build" content="web|local">` in `index.html`.
2. **Otherwise, by where it runs** — `localhost` / `127.0.0.1` / `file:` → `local`; any real
   host → `web`.

So the deployed site is automatically the **web** entity, and anything you run on your machine
is automatically the **local** entity — no configuration needed. (You can still preview the web
entity locally with `…/?build=web` for side-by-side comparison.)

## Practical notes

- Running both at once is fine and expected — they won't interfere.
- Your last scan, cached database, and freshness history live **per entity**. The local entity
  remembers your local history; the web entity has its own. That's intentional.
- Upgrading from a pre-1.1 build: the old single `stale-db` database is deleted automatically on
  first launch (it predates the local/web split).
