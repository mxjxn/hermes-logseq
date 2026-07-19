# Hermes Logseq Stack

Template repo for connecting a **Hermes Agent** to a **Logseq knowledge graph** — with a headless API server, auto-reindexing, a web viewer, and ready-made Hermes skills.

## What You Get

- **logseqd** — Headless Clojure Datalog API for your Logseq graph (query pages, blocks, tags)
- **Notes Viewer** — Zero-build vanilla JS web app for browsing your graph in any browser
- **Auto-reindexing** — inotify watcher triggers instant reindex on any file change
- **Git sync** — Optional git watcher for desktop-assisted workflows
- **Hermes Skills** — Three skills for your agent: core integration, viewer config, cron patterns
- **Installer** — One `setup.sh` to configure everything

## Two Modes

### Headless (Hermes-only)
Hermes writes markdown → inotify → logseqd → viewer. No Logseq desktop needed.

### Desktop-Assisted  
Logseq desktop → git push → git watcher → files → inotify → logseqd → viewer.

Same stack. Different sync story.

## Quick Start

```bash
git clone --recurse-submodules https://github.com/mxjxn/hermes-logseq.git
cd hermes-logseq
./setup.sh
```

The installer will ask you:
- Where your Logseq graph lives
- Which port to run logseqd on
- Headless or desktop mode
- Whether to install the web viewer

It handles dependency detection, PM2 process setup, watcher configuration, and Hermes skill installation.

## Requirements

- **Babashka** (Clojure runtime) — [install](https://babashka.org)
- **inotify-tools** — `apt install inotify-tools` (Linux) or `brew install inotify-tools` (macOS)
- **PM2** (recommended, not required) — `npm install -g pm2`
- **A Logseq graph** — a directory with `pages/` and `journals/` subdirectories

## Project Structure

```
hermes-logseq/
├── logseqd/              # logseqd API server (git submodule)
├── viewer/               # Notes Viewer web app
│   ├── index.html
│   ├── app.js
│   ├── style.css
│   ├── sw.js
│   ├── manifest.json
│   └── icons/
├── scripts/
│   ├── setup.sh          # Interactive installer
│   ├── inotify-watcher.sh  # Auto-reindex on file changes
│   └── git-watcher.sh      # Auto-pull from GitHub
├── skills/
│   ├── hermes-logseq/       # Core skill — architecture, block format, API
│   │   ├── SKILL.md
│   │   ├── references/
│   │   └── scripts/
│   ├── hermes-logseq-viewer/  # Viewer deployment and config
│   │   └── SKILL.md
│   └── hermes-logseq-cron/     # Cron patterns for check-ins and publishing
│       └── SKILL.md
└── README.md
```

## Skills

Three focused Hermes skills, each independently useful:

| Skill | Purpose |
|-------|---------|
| `hermes-logseq` | Core integration — architecture, block format rules, API reference, file organization |
| `hermes-logseq-viewer` | Viewer deployment — reverse proxy setup, customization, PWA config |
| `hermes-logseq-cron` | Cron patterns — check-ins, research pipelines, publishing, read-back workflows |

Enable in your Hermes config:
```yaml
enabled_skillsets:
  - hermes-logseq
  - hermes-logseq-viewer
  - hermes-logseq-cron
```

## What is logseqd?

A lightweight headless server that reads your Logseq graph files into a Datalog database (DataScript) and exposes them via a REST API. Written in Clojure, runs on Babashka.

Key endpoints: `/pages`, `/page/:title`, `/search`, `/query` (Datalog), `/reindex-file`, `/append`.

See the [logseqd repo](https://github.com/mxjxn/logseqd) for full API docs and implementation details.

## What is the Viewer?

A single-page web app with no build step, no framework, no npm dependencies. Serves your Logseq graph to any browser with full block tree rendering, search, journal view, tag browsing, and a compose bar for appending blocks.

## License

MIT
