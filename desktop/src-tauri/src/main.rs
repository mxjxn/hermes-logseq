//! Hermes-Logseq desktop — Phase 1 proof of concept.
//!
//! Topology mirrors the deployed web stack (Caddy in front of logseqd):
//!   webview ── http://127.0.0.1:<app_port> ──▶ axum server (this process)
//!                                               ├─ /api/*  → proxy to logseqd sidecar (strip /api)
//!                                               └─ else    → static viewer/ files
//! The viewer needs zero changes: it keeps calling same-origin /api/*.
//!
//! Sidecar: java -jar logseq-datalog.jar <graph-dir> <port>, loopback only
//! (the daemon binds 127.0.0.1 itself — verified in Phase 0). Graph comes from
//! $LOGSEQ_GRAPH; without it a disposable demo graph is created in the temp dir.

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::{
    net::{TcpListener, TcpStream},
    path::{Path, PathBuf},
    process::{Child, Command, Stdio},
    sync::Mutex,
    time::{Duration, Instant},
};

use axum::{
    body::Body,
    extract::{Request, State},
    http::header,
    response::Response,
    routing::any,
    Router,
};
use tower_http::services::ServeDir;

const SIDECAR_STARTUP_TIMEOUT: Duration = Duration::from_secs(120);
const MAX_BODY: usize = 64 * 1024 * 1024;

#[derive(Clone)]
struct AppState {
    sidecar_port: u16,
    viewer_dir: PathBuf,
}

struct Sidecar(Mutex<Option<Child>>);

fn main() {
    tauri::Builder::default()
        .setup(|app| {
            let graph_dir = resolve_graph_dir();
            let sidecar_port = free_port().map_err(|e| format!("no free sidecar port: {e}"))?;
            let java = java_path(app);
            let jar = jar_path(app).to_string_lossy().into_owned();

            eprintln!(
                "[hermes-logseq] sidecar: {} -jar {} \"{}\" {}",
                java.display(),
                jar,
                graph_dir.display(),
                sidecar_port
            );
            let child = Command::new(&java)
                .arg("-jar")
                .arg(&jar)
                .arg(graph_dir.to_string_lossy().into_owned())
                .arg(sidecar_port.to_string())
                .stdout(Stdio::inherit())
                .stderr(Stdio::inherit())
                .spawn()
                .map_err(|e| format!("failed to spawn sidecar ({} -jar {}): {e}", java.display(), jar))?;
            app.manage(Sidecar(Mutex::new(Some(child))));

            // Jetty only starts listening AFTER the blocking full-graph index
            // (Phase 0: ~3s per 1.6k-page graph on the JVM; large graphs take longer).
            wait_for_listener(sidecar_port, SIDECAR_STARTUP_TIMEOUT)
                .map_err(|_| format!("logseqd not listening on {sidecar_port} within {}s — check graph path", SIDECAR_STARTUP_TIMEOUT.as_secs()))?;
            eprintln!("[hermes-logseq] sidecar healthy on 127.0.0.1:{sidecar_port}");

            let app_port = free_port().map_err(|e| format!("no free app port: {e}"))?;
            let viewer_dir = viewer_dir(app);
            let state = AppState {
                sidecar_port,
                viewer_dir: viewer_dir.clone(),
            };
            eprintln!(
                "[hermes-logseq] serving viewer ({}) + /api proxy on http://127.0.0.1:{}",
                viewer_dir.display(),
                app_port
            );
            tauri::async_runtime::spawn(serve(app_port, state));

            let url: tauri::Url = format!("http://127.0.0.1:{app_port}")
                .parse()
                .map_err(|e| format!("bad app url: {e}"))?;
            tauri::WebviewWindowBuilder::new(app, "main", tauri::WebviewUrl::External(url))
                .title("Hermes Logseq")
                .inner_size(1240.0, 840.0)
                .build()?;
            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("error while building tauri application")
        .run(|app_handle, event| {
            if matches!(
                event,
                tauri::RunEvent::ExitRequested { .. } | tauri::RunEvent::Exit
            ) {
                if let Some(child) = app_handle.state::<Sidecar>().0.lock().unwrap().as_mut() {
                    let _ = child.kill();
                    let _ = child.wait();
                    eprintln!("[hermes-logseq] sidecar stopped");
                }
            }
        });
}

// ─── paths ──────────────────────────────────────────────────────────────────

/// Prefer the bundled resource, fall back to the repo-relative dev path.
/// CARGO_MANIFEST_DIR is desktop/src-tauri, so "../.." is desktop/.. = repo root.
fn resource_or_dev(app: &tauri::AppHandle, resource_rel: &str, dev_rel: &str) -> PathBuf {
    if let Ok(p) = app
        .path()
        .resolve(resource_rel, tauri::path::BaseDirectory::Resource)
    {
        if p.exists() {
            return p;
        }
    }
    Path::new(env!("CARGO_MANIFEST_DIR")).join(dev_rel)
}

fn java_path(app: &tauri::AppHandle) -> PathBuf {
    // Bundled jlink runtime if present (built with JLINK=1, copied into
    // src-tauri/resources/jrt), else the jlink dev output, else system java.
    let candidates = [
        resource_or_dev(app, "resources/jrt/bin/java", "../../target/jrt/bin/java"),
        resource_or_dev(app, "jrt/bin/java", "../../target/jrt/bin/java"),
    ];
    for c in candidates {
        if c.exists() {
            return c;
        }
    }
    PathBuf::from("java")
}

fn jar_path(app: &tauri::AppHandle) -> PathBuf {
    resource_or_dev(app, "resources/logseq-datalog.jar", "../../target/logseq-datalog.jar")
}

fn viewer_dir(app: &tauri::AppHandle) -> PathBuf {
    resource_or_dev(app, "viewer", "../../viewer")
}

/// PoC graph resolution: $LOGSEQ_GRAPH wins; else a disposable demo graph in
/// the temp dir so first run always has something to open.
fn resolve_graph_dir() -> PathBuf {
    if let Ok(dir) = std::env::var("LOGSEQ_GRAPH") {
        return PathBuf::from(dir);
    }
    let demo = std::env::temp_dir().join("hermes-logseq-demo-graph");
    let _ = std::fs::create_dir_all(demo.join("pages"));
    let _ = std::fs::create_dir_all(demo.join("journals"));
    let readme = demo.join("pages").join("Welcome.md");
    if !readme.exists() {
        let _ = std::fs::write(
            &readme,
            "type:: page\n\n- Welcome to the Hermes-Logseq desktop proof of concept\n\t- Edit me — this demo graph is disposable and lives in your temp dir\n- Set LOGSEQ_GRAPH to open a real (copied!) graph — see desktop/README.md\n",
        );
    }
    demo
}

// ─── sidecar supervision ────────────────────────────────────────────────────

fn free_port() -> std::io::Result<u16> {
    let l = TcpListener::bind("127.0.0.1:0")?;
    let port = l.local_addr()?.port();
    drop(l); // small TOCTOU race; acceptable for the PoC
    Ok(port)
}

/// The daemon's jetty listener only comes up after the full index, so a TCP
/// connect is a solid readiness signal for the PoC (HTTP /health is polled by
/// build-jar.sh's smoke test).
fn wait_for_listener(port: u16, timeout: Duration) -> Result<(), ()> {
    let start = Instant::now();
    while start.elapsed() < timeout {
        if TcpStream::connect(("127.0.0.1", port)).is_ok() {
            return Ok(());
        }
        std::thread::sleep(Duration::from_millis(400));
    }
    Err(())
}

// ─── app server: static viewer + /api proxy ─────────────────────────────────

async fn serve(port: u16, state: AppState) {
    let viewer = ServeDir::new(&state.viewer_dir);
    let router = Router::new()
        .route("/api", any(proxy))
        .route("/api/", any(proxy))
        .route("/api/*path", any(proxy))
        .fallback_service(viewer)
        .with_state(state);
    match tokio::net::TcpListener::bind(("127.0.0.1", port)).await {
        Ok(listener) => {
            if let Err(e) = axum::serve(listener, router).await {
                eprintln!("[hermes-logseq] app server died: {e}");
            }
        }
        Err(e) => eprintln!("[hermes-logseq] cannot bind app port {port}: {e}"),
    }
}

/// Reverse-proxy /api/* to the sidecar. The daemon serves routes WITHOUT the
/// /api prefix (Caddy `handle_path` equivalent). Never touch the body — the
/// API is EDN-native and the viewer already speaks it.
async fn proxy(State(st): State<AppState>, req: Request<Body>) -> Response {
    let (parts, body) = req.into_parts();
    let pq = parts
        .uri
        .path_and_query()
        .map(|pq| pq.as_str().to_owned())
        .unwrap_or_else(|| "/".into());
    let stripped = pq.strip_prefix("/api").unwrap_or(&pq);
    let stripped = if stripped.is_empty() { "/" } else { stripped };
    let target = format!("http://127.0.0.1:{}{}", st.sidecar_port, stripped);

    let bytes = match axum::body::to_bytes(body, MAX_BODY).await {
        Ok(b) => b,
        Err(e) => return json_error(400, &format!("failed to read request body: {e}")),
    };

    let client = match reqwest::Client::builder().build() {
        Ok(c) => c,
        Err(e) => return json_error(500, &format!("proxy client error: {e}")),
    };
    let method = parts.method.clone();
    let mut out = client.request(method, &target);
    for (name, value) in parts.headers.iter() {
        if matches!(*name, header::HOST | header::CONTENT_LENGTH) {
            continue;
        }
        if let Ok(v) = value.to_str() {
            out = out.header(name.as_str(), v);
        }
    }
    if !bytes.is_empty() {
        out = out.body(bytes);
    }

    match out.send().await {
        Ok(res) => {
            let status = res.status().as_u16();
            let mut builder = Response::builder().status(status);
            for (name, value) in res.headers() {
                if matches!(*name, header::CONTENT_LENGTH | header::TRANSFER_ENCODING) {
                    continue;
                }
                builder = builder.header(name.clone(), value.clone());
            }
            match res.bytes().await {
                Ok(b) => builder
                    .body(Body::from(b))
                    .unwrap_or_else(|_| json_error(502, "bad upstream response")),
                Err(e) => json_error(502, &format!("upstream body error: {e}")),
            }
        }
        // A real 503 beats a silently-dead fetch (the "stuck on Loading" class
        // of bug from the web app — never leave the renderer hanging).
        Err(e) => json_error(503, &format!("sidecar unreachable: {e}")),
    }
}

fn json_error(status: u16, msg: &str) -> Response {
    Response::builder()
        .status(status)
        .header(header::CONTENT_TYPE, "application/json")
        .body(Body::from(format!(
            "{{\"error\":\"{}\"}}",
            json_escape(msg)
        )))
        .expect("static response parts are always valid")
}

fn json_escape(s: &str) -> String {
    // dependency-free; only used on our own error strings
    s.replace('\\', "\\\\").replace('"', "\\\"")
}
