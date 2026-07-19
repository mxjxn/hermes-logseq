---
visibility: public
name: hermes-logseq-viewer
description: Deploy and configure the Notes Viewer — a static web UI for browsing a Logseq graph via the logseqd API.
version: 1.0.0
metadata:
  hermes:
    tags: [logseq, viewer, web, knowledge-graph]
---

# Hermes Logseq — Notes Viewer

A zero-build, vanilla JS web app that serves your Logseq knowledge graph to any browser. Reads from the logseqd API — no desktop app required.

## What It Does

- Browse all pages with full block tree rendering
- Search across the entire graph
- Journal view with daily entries
- Tag browsing
- Page references and `[[]]` links
- Compose bar for adding blocks
- Mobile-responsive
- PWA-capable (offline, installable)
- Push notifications for changes

## What It Doesn't Do

- No inline editing (compose bar is append-only)
- No `[[]]` link navigation in edit mode
- No `{{query}}` rendering (desktop-only feature)
- No canvas / whiteboard views

## Files

```
viewer/
├── index.html      # Main HTML shell
├── app.js          # All application logic (~82KB, single file)
├── style.css       # Styles (~32KB)
├── sw.js           # Service worker for PWA
├── manifest.json   # PWA manifest
└── icons/          # App icons (touch, favicon, 192px, 512px)
```

No build step. No framework. No npm. Just static files.

## Deployment

### 1. Copy Files

```bash
cp -r viewer/* /var/www/notes-viewer/
```

Or wherever your web server serves static files.

### 2. Configure Reverse Proxy

The viewer expects logseqd at `/api`. You need a reverse proxy:

**Caddy:**
```
notes.example.com {
  root * /var/www/notes-viewer
  file_server
  reverse_proxy /api/* localhost:8471
}
```

**Nginx:**
```nginx
server {
  listen 443 ssl;
  server_name notes.example.com;

  location /api/ {
    proxy_pass http://localhost:8471;
    proxy_set_header Host $host;
  }

  location / {
    root /var/www/notes-viewer;
    try_files $uri $uri/ /index.html;
  }
}
```

**macOS local dev (no reverse proxy):**
Edit `app.js` line 2 to point directly:
```js
const API = 'http://localhost:8471';
```

### 3. Deploy / Update

When editing viewer files, bump the version:
- `index.html`: update `<meta name="version">` and `?v=` on CSS link
- `sw.js`: bump the cache version string

Changes go live immediately (no rebuild).

## Configuration

### Default Page

On first visit (no hash), the viewer loads today's journal. This is hardcoded in `app.js` — search for `hash routing` to change the default landing page.

### Search

Full-text search via logseqd's `/search` endpoint. Searches block content and tags.

### Compose Bar

Append-only. Blocks are added as children of the current page's root level. For journals, they append to the day block.

### Push Notifications

The viewer supports web push notifications via `/api/push/subscribe` and `/api/push/unsubscribe` endpoints. Requires logseqd to implement these — currently a TODO in most setups.

## Customization

- **Site title:** Edit `<h1 id="site-title">` in `index.html`
- **Theme:** Edit CSS variables in `style.css` (search for `:root`)
- **Fonts:** Currently uses Inter + JetBrains Mono (loaded from Google Fonts)
- **GitHub link:** Change in `index.html` footer

## Limitations

- No real-time updates — manual refresh or the compose bar triggers changes
- inotify handles auto-reindex on the server side; the viewer polls on user action
- Block deletion and editing require direct file manipulation + reindex
- No user authentication — the viewer is public by default. Use your web server's auth if needed.
