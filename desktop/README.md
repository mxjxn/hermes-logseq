# Hermes-Logseq Desktop (Phase 1 PoC)

Local-first desktop shell around the existing `viewer/` + `logseqd` stack.
Topology mirrors the deployed web app: a local server serves the viewer and
proxies `/api/*` to the logseqd sidecar — **the viewer needs zero changes**.

```
webview ──▶ 127.0.0.1:<app_port>  (axum, this repo's src-tauri/src/main.rs)
              ├─ /api/*  ──▶ 127.0.0.1:<sidecar_port>  (logseqd uberjar, loopback)
              └─ else    ──▶ static viewer/ files
```

Verified building blocks (Linux, JDK 21 — see `docs/PHASE0-AUDIT.md` §4):
13 MB uberjar + 44 MB jlink runtime, **3.1s cold start**, reads *and writes*
pass on the minimal runtime.

## Prerequisites

- JDK 21+ (`java`, `jar`) and the Clojure CLI (`clojure`) — only for building the jar
- Rust + Tauri CLI: `cargo install tauri-cli --version "^2"`
- macOS: Xcode CLT. Linux dev: `webkit2gtk-4.1`, `libappindicator`, etc. per
  [Tauri prerequisites](https://tauri.app/start/prerequisites/)

## The two commands

```bash
cd desktop
./build-jar.sh                                # 1. build the sidecar (self-smoke-tests it)
LOGSEQ_GRAPH="$PWD/target/dev-graph" cargo tauri dev   # 2. run the shell
```

- `./scripts/dev-graph.sh` creates a disposable test graph (namespace page,
  fenced `[[ref]]`, inline + property-zone `id::`, TODO, journal).
- **No `LOGSEQ_GRAPH`?** The app creates a disposable demo graph in your temp
  dir, so first run always works.
- ⚠️ Phase 1 scope: point `LOGSEQ_GRAPH` at a **copy** of any real graph, or a
  disposable one. Graph create/open/switch UI (with locking and flush) is
  Phase 2 — the daemon indexes exclusively and there is no multi-writer
  protection yet.
- `JLINK=1 ./build-jar.sh` also builds a minimal jlink runtime into
  `target/jrt` (what a bundled app ships instead of a full JDK).

## Layout

| Path | What |
|---|---|
| `build-jar.sh` | AOT-compile + uberjar + smoke test (+ optional `JLINK=1` runtime) |
| `scripts/dev-graph.sh` | disposable fixture graph |
| `src-tauri/src/main.rs` | Tauri app: spawn sidecar → wait for listener → serve viewer + `/api` proxy → open window; kills sidecar on exit |
| `src-tauri/tauri.conf.json` | bundle resources: `resources/logseq-datalog.jar`, `resources/jrt` |
| `viewer/` (repo root) | the frontend, used in place — never forked |

## Building a real app bundle (first `tauri build`)

```bash
cargo tauri icon src-tauri/icons/icon.png   # replace placeholder icon set
JLINK=1 ./build-jar.sh
mkdir -p src-tauri/resources
cp target/logseq-datalog.jar src-tauri/resources/
cp -R target/jrt src-tauri/resources/jrt
cargo tauri build
```

macOS notes: build on the Mac (`jlink` cannot cross-compile); unsigned builds
need right-click → Open on first launch (Gatekeeper); renamed sidecar binaries
with target-triple suffixes (`*-aarch64-apple-darwin`) become relevant when we
move from resources+wrapper to Tauri's native `externalBin` sidecars later.

## Deliberately not in this PoC

Graph lifecycle UI (create/open/recent/switch), write-flush/readiness UX,
signing/notarization, auto-update, multi-window. Those are Phases 2–3 in
`docs/ROADMAP.md`.
