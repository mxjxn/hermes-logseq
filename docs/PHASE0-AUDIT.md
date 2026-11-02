# Phase 0 audit — hermes-logseq desktop

Date: 2026-11-02. Method: source inspection of `/root/logseq-datalog-service` (== pinned submodule `d251b30`, byte-identical) + live baseline run against a disposable graph at `/tmp/phase0-graph` on ports 8491/8493. Production daemons (8471 Max, 8472 Jenn) were never touched. Fixture preserved at `/root/.hermes/cache/scratch/phase0-graph-fixture` (also `/tmp/phase0-graph`).

Corresponds to the Phase 0 checklist in `DESKTOP_PLAN.md` (2026-10-30, ChatGPT road-trip document).

## 1. Plan corrections (claims that are already stale)

| Plan claim | Verified reality |
|---|---|
| "GitHub writes returned HTTP 403" | Two commits landed on origin/main Oct 29–30 (`1ef12b0`, `c7ab30f`, pushed from the Mac). The 403 was the ChatGPT connector's limitation. Writes from the VPS work (git+ssh). |
| "does not explicitly bind to loopback" | **Fixed** at the current pin: `core.clj` runs Jetty with `{:host "127.0.0.1" :port port}` (commit `d251b30` "Bind Jetty to loopback explicitly"). |
| "Repository: mxjxn/hermes-logseq" | **Correct.** GitHub renamed the repo from Mnemosyne; `mxjxn/hermes-logseq` is canonical (confirmed by GitHub's moved-repo notice and direct `ls-remote` at push time, 2026-11-02). The Oct 29 commit only changed README wording; the rename itself happened on GitHub. VPS remote updated accordingly. |
| inotify watcher semantics (Linux-only) | Confirmed. Bash + `inotifywait`, watches `pages/` + `journals/` only, `.md` only, 0.5s debounce, POSTs `/reindex-file`. No macOS equivalent exists in the project. |

## 2. Endpoint inventory

Backend (`api.clj` router) — 26 routes:
`GET /query, /health, /pages, /library, /graph, /page/<title>, /tags, /search, /property, /templates, /properties-schema, /block/<uuid>, /block/<uuid>/refs, /assets/<path>` +
`POST /create-page, /append, /update-block, /insert-block, /delete-block, /change-block-level, /reindex, /reindex-file, /set-page-property, /push/subscribe, /push/unsubscribe, /upload`

Viewer (`app.js`) calls **20 distinct endpoints**:
- via `api()`/`apiPost()`: append(×5), page/(×3, dynamic), pages(×2), update-block, templates, tags, search, library, insert-block, health, graph, delete-block, change-block-level
- via `fetch(API + '…')`: **query (×2)**, templates, properties-schema, create-page
- via raw fetch: push/subscribe, push/unsubscribe

**Backend routes with no viewer caller (9):** `/property` (gate whitelist), `/reindex` (manual), `/reindex-file` (watcher), `/set-page-property` (publish toggle — UI still pending), `/upload` + `/assets/` (backend works; **no frontend anywhere** — see 3.1), `/block/<uuid>` + `/block/<uuid>/refs` (backlinks/block-ref surface the prototype targets), `/query` is NOT in this list — the viewer itself queries (ghost-page backlinks + tag pages).

Classification for the desktop build: the 20 viewer-called endpoints are the standalone-notes essential set. The 9 uncalled routes split into: watcher-infra (reindex-file), publishing track (property, set-page-property), upload feature (upload/assets), and backlinks primitives (block, block/refs).

## 3. Findings

### Data-integrity / API hazards (fix or guard before multi-client use)

1. **Journal split-brain.** `/append` routes purely on the `:journal` flag — there is no date-title detection. `{ :title "2026_11_02" :content … }` without `:journal true` created `pages/2026_11_02.md`; afterwards `/page/2026_11_02` returned ONLY the duplicate, shadowing the real journal in the index (verified live). Any agent/Tauri client that forgets the flag silently forks a journal page. Suggested guard: if title matches `^\d{4}_\d{2}_\d{2}$` and `journals/<title>.md` exists, route there (or refuse).
2. **Every write shifts all block IDs.** Verified: 5 writes took IDs from `Alpha-1…6` → `Alpha-32…37`. A restart regenerates the whole set (`Alpha-32…` → `Alpha-7…`). Consequence: full re-render after every mutation (already the viewer's pattern) and mandatory reload after restart (the known hard-refresh rule — the desktop app must do this automatically).
3. **Keyword EDN keys corrupt created properties.** `/create-page` with `{:properties {:type "source"}}` wrote `:type:: source` (leading colon) into the .md file — invalid Logseq properties. String keys (`{:properties {"type" "source"}}`) are required. Fragile for future clients; worth validating/coercing server-side.
4. **File rewrites drop the EOF newline.** After `/insert-block`, `Alpha.md` ended without `\n`; a subsequent external append glued onto the last block (`still same block- EXTERNAL edit line`). `/append` explicitly guards for this; `/update-block` and `/insert-block` do not.
5. **EDN-only API, inconsistent key names.** JSON bodies → `500 {"error":"Invalid token: :"}`. Keys vary per route: `:id` (update-block) vs `:block-id` (delete/change-level) vs path param `:uuid` (block). Fine for the existing viewer; document before the Tauri sidecar or any agent writes against it.

### Backend behavior gaps measured on the fixture

6. **Namespaced pages are broken at the index level.** `pages/deep/Nested Page.md` is indexed as a ghost entity (title present in `/pages`, but no `page/file`, no mtime). `/page/deep/Nested Page` **and** `/page/deep___Nested Page` both 404. `/library` drops it (2 of 3 real pages listed). `/graph` returned **1 node / 0 edges** on a 3-page interlinked graph (Alpha↔Beta↔Nested) — worse than namespace-only; repro preserved. Max's real graph works (146 nodes/347 edges) but it may simply contain no namespaced files.
7. **`/block/<uuid>` only sees property-zone `id::` lines.** Inline `id:: <uuid>` at the end of a bullet line (real Logseq writes both styles) is never indexed as `:block/uuid` → 404. Property-zone form works, and `/block/<uuid>/refs` correctly resolves `((uuid))` references (verified count=1). Compat gap for the backlinks prototype's "click a reference → open source block".
8. **`/library` snippet picks the wrong block.** The server returns children before parents in the flat block list; the library handler takes the first block as snippet, so a child's text becomes the card snippet (verified: Alpha's card shows its child block). The client-side `docOrder()` fix doesn't exist server-side.
9. **Ghost backlinks are substring queries.** `loadGhostPage()` uses `clojure.string/includes?` over all block content — "Alpha" matches "Alphabet". Ghost pages also have no indexed blocks, so ghost→ghost backlinks are invisible. The prototype's indexed-refs approach is the right fix.

### Confirmed-good behavior (baseline to protect)

- Multi-line round-trip: continuation lines written with correct indent (v0.0.30 fix holds).
- Fence-stripping: `[[NotARealPage]]` inside a code fence is NOT extracted as a ref/tag (v0.0.42 parser fix holds).
- `/reindex-file` external-change path works; mtime dedup prevents write+watcher double-indexing.
- `/set-page-property` add+remove round-trip works (stale-property index fix holds).
- Upload endpoint works standalone (returns `../assets/<uuid>-upload` + `/api/assets/...` URL).
- Search dedupes by page, caps blocks/page (privacy filtering lives in the same handler on the live graph).
- Journal reads carry `block/line` + `block/end-line` spans (what the Desktop plugin requires for edits).

### 3.1 Repo/deploy parity

- `viewer/app.js` repo == deployed (no drift right now).
- `index.html` differs only in the GitHub footer link (repo says `hermes-logseq`, deployed says `Mnemosyne`).
- **Image upload has no frontend anywhere** — zero `upload` references in repo `viewer/` history (`git log -S upload` empty), deployed editor, or jeeby. The skill records it as shipped v0.0.33–34; it was likely hot-patched into a deployed file and later wiped by a repo→deploy copy (the known Jul 2026 failure mode). Needs Max's confirmation whether the 📎 button still exists on his phone.

## 4. Packaging measurements (Linux, verified by running)

| Artifact | Size | Notes |
|---|---|---|
| Dependency jars | 39 jars / 10.2 MB | classpath of the running service |
| AOT uberjar (`:gen-class` on core) | **13 MB** | `java -jar` runnable, Main-Class `logseq_datalog.core` |
| jlink runtime | **44 MB** | modules: `java.base,java.logging,java.naming,java.xml,java.sql,jdk.unsupported` |
| Combined payload | **~57 MB** | vs ~300 MB full JDK |

- **Cold start via `clojure -M:run`: 10.3s** (tiny graph; JVM boot + CLI tooling + blocking full index).
- **Cold start via `java -jar` on the jlink runtime: 3.1s** — and the full app was smoke-tested on it: health, page read, **write** (`/append`), search all pass. The curated module set is sufficient (jdeps cannot produce the set automatically — jetty's optional JMX and the jackson cbor→databind→annotations chain break its resolution; derive + verify by smoke test instead).
- Startup is a **blocking full-graph index before the server listens**. Tiny graph: ~3s; Max's 1,612-page graph: ~30–60s (observed in pm2, consistent). Restart-per-graph switching (plan item 7) inherits this stall — readiness UX is mandatory, concurrent indexing stays a later optimization.
- Termination: no shutdown hook; Jetty `:join? true`; process kill is the only stop. Safe with the current write model (every request writes through to disk immediately; no dirty in-memory state).
- **macOS sidecar/JVM numbers: unverified from this box.** Linux evidence supports "child process + jlink runtime" as the packaging default (plan's stated default).

## 5. Immediate-next-step recommendations (feeding the plan's "Next concrete task")

1. Tauri PoC can proceed on the verified shape: sidecar = uberjar + jlink runtime (57 MB), loopback bind already in code, `/api/*` proxy unchanged.
2. Before the PoC ships writes: fix #1 (journal routing guard) and #4 (EOF newline) in `api.clj` — both small, both protect the "never destructive" acceptance criterion.
3. The backlinks prototype should target `/block/<uuid>/refs` (verified working) and add inline-`id::` indexing (#7) to the logseqd backlog.
4. `/graph` and `/library` need namespace fixes before the desktop "library/graph" views can be trusted on graphs with folders (#6) — plus the snippet-order fix (#8).
5. Build the P3 fixture corpus starting from `/root/.hermes/cache/scratch/phase0-graph-fixture` (it already encodes findings #6–#8 as failing cases).
