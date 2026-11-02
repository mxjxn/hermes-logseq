# Hermes-Logseq Desktop — implementation plan

Status: planning document only. No code or GitHub branch has been created. GitHub writes returned HTTP 403. Prepared 2026-10-30.

## Product boundaries

- **Notes desktop app**: local-first, standalone Logseq-compatible Markdown editor. No Hermes installation, AI account, or manually managed service required.
- **Optional Hermes integration**: separate installation/configuration that lets an agent access the graph via `logseqd` or a compatible API. Keep the agent features out of the default onboarding experience.
- **Existing web editor and public reader**: preserve as separate deployment modes; do not require public publishing or hosting for desktop use.

## Confirmed current repository architecture

Repository: `mxjxn/hermes-logseq`, default branch `main`.

- `viewer/` is a static HTML/CSS/JavaScript editor; it calls `/api/*`.
- `logseqd/` is a pinned Clojure/JVM submodule providing graph indexing, parsing, querying, and file editing. `docs/deployment.md` launches it with `clojure -M:run /absolute/path/to/graph 8471` and routes `/api/*` to the daemon without the `/api` prefix.
- The current daemon is configured for a single graph at startup. Restart-on-switch is the initial proposal, pending validation.
- The existing Linux watcher uses `inotify-tools`; there is no native macOS watcher checked into the project. Direct API writes reindex affected files.
- The raw daemon API does not implement the private editor's authentication layer; do not expose it to the network by default.
- Existing `setup.sh` is described as legacy and should not be treated as a working installer.

## First release scope

1. Desktop wrapper using Tauri, reusing the existing `viewer/` frontend.
2. Bundle and supervise the `logseqd` backend and required runtime so users do not install Clojure/Java manually. Evaluate JVM packaging (`jlink` runtime, executable JAR/launcher) and Tauri sidecar behavior on both platforms before committing to a packaging approach.
3. First-run screen: **Create graph** or **Open existing graph**.
4. Create graph in user-selected directory, initializing `pages/` and `journals/` and only other Logseq-compatible files actually required by the app.
5. Open an existing Logseq Markdown graph in place; never migrate or rewrite the whole graph without explicit consent. Preserve files, indentation, block IDs, page references, and properties.
6. Remember recently opened graph paths and last active graph in application settings (outside the graph). Support switching graphs from a visible selector.
7. On switch: block new edits, flush/debounce pending writes, stop the backend, start it for the target graph, wait for health/index readiness, then load the target graph. Roll back to previous graph on failure. Never mix cached state between graphs.
8. Save and recover gracefully on shutdown, crash, unavailable paths, or locked files. Avoid concurrent writers and accidental destructive modifications.
9. Run the backend on loopback only, with random/available port and appropriate access controls. Assess Tauri-to-backend API routing, CSRF/origin restrictions, and protection from other local processes; do not rely on an open unauthenticated HTTP listener.
10. Support Linux development and packaging, with macOS as the intended first public audience. Unsigned macOS builds can be tested but will encounter Gatekeeper friction; signing/notarization is a later release requirement.

## Implementation sequence

### Phase 0 — verify architecture and compatibility
- Inventory all `viewer/` API calls and backend endpoints; confirm which are essential for standalone notes versus agent/publishing workflows.
- Inspect `logseqd` build/dependencies and startup/termination behavior, indexing, and file-watcher semantics.
- Run a disposable graph through the current editor; record baseline read/edit/search/journal behavior and test coverage.
- Validate macOS and Linux sidecar/JVM bundle sizes and startup times. Decide whether the packaged backend remains a child process or becomes an embedded library; default to child process to minimize rewrites.

### Phase 1 — minimal local desktop proof of concept
- Add a Tauri shell loading `viewer/`.
- Start and supervise bundled backend with an isolated test graph; proxy frontend `/api/*` calls correctly.
- Add diagnostics for startup failure, logs, and graceful stop.
- Test offline operation, application restart, and preservation of files.

### Phase 2 — graph lifecycle
- Implement create/open/recent/switch UI and native directory picker.
- Add backend restart on graph change with pending-write flush, readiness checks, cache reset, and failure recovery.
- Test graphs with spaces/unicode in paths, empty graphs, large graphs, deleted/moved graphs, and simultaneous access by Logseq.

### Phase 3 — distribution
- Package Linux build (AppImage/deb as appropriate) and unsigned macOS build for internal testing.
- Set up GitHub Actions builds once repository write access is resolved.
- Verify no external Java/Clojure/Node install is required by end users; test on clean machines.
- Document Apple signing/notarization path and release limitations.

### Phase 4 — optional integrations
- Document how Hermes connects to the desktop graph without making it a prerequisite for note taking.
- Consider separate remote API and public publishing setup, with explicit permissions and opt-in.

## Acceptance criteria for initial milestone

- A nontechnical user installs and launches the app without opening a terminal.
- User can create a graph, edit a journal/page, quit, relaunch, and see changes preserved in Markdown.
- User can open an existing Logseq Markdown graph without conversion.
- User can switch between two graphs with no cross-contamination or lost edits.
- App works without an AI agent, external network, or separately installed JVM/Clojure.
- Backend is stopped when the app exits; failures are recoverable and actionable.

## Risks / unresolved decisions

- JVM distribution and native launcher footprint on macOS/Linux, including architecture-specific binaries.
- Correct secure local HTTP binding: current launcher specifies port but does not explicitly bind to loopback, per `docs/deployment.md`.
- Cross-platform external file change detection: Linux watcher is not macOS-compatible.
- Logseq Markdown compatibility is a goal, not yet a guarantee for all syntax and metadata. Build a compatibility test corpus before claiming full compatibility.
- Multiple graph indexes: restart-per-graph initially; measure performance before introducing concurrent indexing.
- GitHub branch and commits cannot currently be created through the connected integration (403 Resource not accessible by integration). This plan is a local artifact, not a repository change.


## Feature-parity and usability roadmap (added 2026-10-30)

**Product principle:** Prioritize a strong Markdown-compatible, human-operated notes editor over adding agent features. The user's core workflow is journaling, browsing thousands of notes, and reading/editing research documents written by Hermes. The optional agent integration remains separate. Target practical parity with **file-based Logseq** for the workflows below, not every Logseq feature or an identical UI.

### P0 — Navigation, discovery, and linked references

- [ ] **Linked references on all pages**, including existing pages and pages with no backing file; clicking a reference opens its source block. Do not create empty files just by navigating.
- [ ] **Accurate reference matching:** unify `#topic` and `[[topic]]` topic navigation; avoid false positives from substring searches; verify the backend's indexed page/tag relations. Existing `loadGhostPage()` and `loadTagPage()` provide a starting point, but populated pages lack a backlinks section. A separate prototype and patch archive were prepared (`hermes-logseq-backlinks-integration.zip`); not applied to GitHub or runtime-tested.
- [ ] **Full-text search** across page titles and blocks with excerpts, highlighting, relevance ranking, and useful keyboard navigation; benchmark with thousands of documents.
- [ ] **Library/document browser** with filters for tags, page properties, dates, and namespaces; browsing should not be limited to recent-edit/alphabetical lists.
- [ ] **Related pages** derived initially from explicit links, backlinks, and shared tags; no embedding or AI dependency for the first iteration.
- [ ] **Command palette / quick switcher** for jumping to pages and blocks and invoking common actions.

### P1 — Outliner and document editing

- [ ] Audit block creation, indent/outdent, collapse/expand, hierarchical movement, reordering, keyboard traversal, and undo/redo against file-based Logseq.
- [ ] Audit individual block references and embeds/transclusion; preserve reference IDs and Markdown syntax even before full interactive parity.
- [ ] Improve editing long agent-authored research documents: reorganize sections, edit text, and preserve source links without awkward block-by-block friction.
- [ ] Handle simultaneous edits by the human editor and external tools/agents: detect stale writes, preserve both versions on conflict, and provide recovery. Test autosave and crash recovery.
- [ ] Make source links and provenance easy to inspect from research notes.

### P2 — Structured notes and daily workflows

- [ ] Audit journal navigation and capture workflows, including reusable templates and journal templates.
- [ ] Audit page and block properties, aliases, namespaces, and structured queries. Provide discoverable UI for metadata rather than requiring Datalog knowledge.
- [ ] Audit basic TODO/task behavior and queryability, but defer advanced scheduling and deadline UX unless user demand changes.
- [ ] Add accessible revision/history inspection and recovery; Git history alone is insufficient as end-user UX.

### P3 — Compatibility, quality, and distribution

- [ ] Build a **real Logseq Markdown fixture corpus** covering nested blocks, page and block references, tags, aliases, properties, journals, templates, and tricky Unicode/file paths. Test round trips without destructive rewrites.
- [ ] Test large-graph performance, indexing latency, file watching, and edits made outside the application.
- [ ] Maintain separate desktop packaging track (Tauri + bundled `logseqd`, graph creation/opening/switching) described above.
- [ ] Treat agent collaboration, plugin APIs, and enhanced publishing as later enhancements, not prerequisites for everyday note-taking parity.

### Explicitly not required for first parity milestone

Flashcards, whiteboards, and multi-document/right-sidebar editing are not priorities. Advanced task scheduling and AI-based related-note recommendations are also deferred.

### Audit method and status definitions

For each item, inspect `viewer/`, the pinned `logseqd/` submodule, and tests; compare behavior with **file-based Logseq**, not just feature names. Record **implemented**, **partial**, **missing**, or **unverified**, with source paths and reproduction steps. Do not mark a feature missing solely because repository search returns no match. Verify behavior in a disposable graph, then test with a realistic large graph. The checklist above is a **prioritized audit backlog**, not a claim that every unchecked item is absent.

### Immediate next actions

1. Validate the linked-references patch against the real daemon and both populated/ghost pages; ensure errors are not displayed as zero results.
2. Audit existing search endpoints and UI, then prototype relevance-ranked results and quick navigation.
3. Audit the library view and design filters/related-page affordances.
4. Continue desktop packaging in parallel, without making it a dependency for navigation improvements.

## Next concrete task

Create a small Tauri proof of concept that launches `logseqd` against a disposable graph and serves the existing viewer with API requests correctly routed. First audit the existing viewer endpoints and backend packaging prerequisites; do not modify the user's live graph.


## Optional Hermes integration — selective knowledge retrieval architecture (2026-10-30)

**Scope:** This is an optional agent-integration track, separate from the P0–P3 Logseq feature-parity work and the Tauri desktop packaging track. The existing roadmap focuses on navigation/search and does not specify a complete automatic retrieval pipeline. The following design reconciles the new discussion without displacing those priorities.

### Agreed behavior
- Retrieval is **selective**, not a lookup or relevance evaluation on every model call.
- The `logseqd` graph and Markdown files remain the source of truth; automatic retrieval is read-only.
- The main agent should see a compact, cited evidence packet, not the retrieval worker's exploratory tool results, rejected documents, or intermediate reasoning.
- Existing manual search and document-editing tools remain available.

### Proposed request path
1. **Trigger:** Hermes decides a graph lookup is useful (e.g., resuming documented work or needing project-specific facts). The precise trigger policy is **unresolved**; do not claim that instructions alone reliably detect every opportunity. Consider explicit events and agent-initiated tool calls. No per-call scanning.
2. **Isolated worker:** A separate invocation or subagent receives the question and bounded relevant context; it queries `logseqd`, follows references/backlinks as needed, and evaluates candidates within time/token limits.
3. **Evidence packet:** Worker returns only selected page/block excerpts, source IDs/paths, retrieval timestamp, and enough parent context to make blocks intelligible. Deduplicate, rank, and cap total tokens. No irrelevant intermediate results are returned.
4. **Answer:** Hermes receives the compact packet and continues in its normal agent loop. Worker context is discarded; the stored main conversation remains intact.
5. **Optional later context-engine work:** If the *main* conversation is already bloated, evaluate a custom `select_context()` implementation to construct a smaller request from original question, necessary conversation state, and evidence packet. This is not needed for isolated retrieval alone and must preserve Hermes's normal compression and tool-call semantics.

### Implementation boundaries and verification
- Start with an isolated retrieval tool/subagent, not a custom memory provider or context engine.
- Confirm Hermes subagent isolation, tool-result serialization, and when/how the next model call consumes the evidence packet.
- Inspect the actual `select_context()` call path before committing to a context-engine plugin; determine whether one active engine replaces existing compaction and how tool-call/result pairs are preserved.
- Test retrieval trigger precision/recall (including missed lookups), relevance quality, source traceability, latency, token savings, and fallback when `logseqd` is unavailable.
- Keep a user-visible retrieval trace: what triggered the lookup, selected sources, and budget consumed, without exposing private model reasoning.
- Do not automatically write back memories or modify Markdown during retrieval.

### Open decisions
- What events reliably trigger retrieval without evaluating every turn?
- Which retrieval ranking signals are already available from `logseqd` versus requiring new APIs?
- Is an isolated subagent sufficient, or do long conversations require a context-engine replacement?
- How will graph switching and permissions scope retrieval to the active graph?

**Suggested milestone:** Prototype a manually invoked isolated worker against a disposable graph; verify it returns a compact, sourced packet and that rejected results never reach the main context. Then test selective triggering. Only then assess a custom context engine.
