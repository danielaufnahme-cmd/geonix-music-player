//! Geonix Music Player backend.
//!
//! HTTP API on 127.0.0.1:7878 for the Flutter app. Owns the SQLite library,
//! the download queue and the Python worker process.
//!
//! Environment overrides (all optional):
//!   GEONIX_PORT       port to listen on (default 7878)
//!   GEONIX_DATA_DIR   database + cover cache (default ~/.local/share/geonix)
//!   GEONIX_MUSIC_DIR  where MP3s are saved (default ~/Music/Geonix)
//!   GEONIX_PYTHON     python interpreter (default worker/.venv/bin/python, else python3)
//!   GEONIX_WORKER     path to worker.py (default ../worker/worker.py next to this crate)

mod db;
mod downloads;
mod error;
mod models;
mod routes;
mod worker;

use std::collections::HashMap;
use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use tracing_subscriber::EnvFilter;

use crate::db::Db;
use crate::downloads::DownloadManager;
use crate::routes::AppState;
use crate::worker::{Worker, WorkerConfig};

fn env_path(key: &str) -> Option<PathBuf> {
    std::env::var_os(key).filter(|v| !v.is_empty()).map(PathBuf::from)
}

fn home() -> PathBuf {
    dirs::home_dir().unwrap_or_else(|| PathBuf::from("."))
}

fn worker_config() -> WorkerConfig {
    let script = env_path("GEONIX_WORKER")
        .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("..").join("worker").join("worker.py"));
    let python = env_path("GEONIX_PYTHON").unwrap_or_else(|| {
        let venv = script.parent().map(|d| d.join(".venv").join("bin").join("python"));
        match venv {
            Some(p) if p.exists() => p,
            _ => PathBuf::from("python3"),
        }
    });
    WorkerConfig { python, script }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")))
        .init();

    let data_dir = env_path("GEONIX_DATA_DIR").unwrap_or_else(|| {
        dirs::data_dir().unwrap_or_else(|| home().join(".local").join("share")).join("geonix")
    });
    let music_dir = env_path("GEONIX_MUSIC_DIR").unwrap_or_else(|| home().join("Music").join("Geonix"));
    let covers_dir = data_dir.join("covers");
    for dir in [&data_dir, &music_dir, &covers_dir] {
        std::fs::create_dir_all(dir)?;
    }
    let port: u16 = std::env::var("GEONIX_PORT").ok().and_then(|p| p.parse().ok()).unwrap_or(7878);

    let db = Arc::new(Db::open(&data_dir.join("library.db"))?);
    let interrupted = db.fail_interrupted_downloads()?;
    if interrupted > 0 {
        tracing::info!("{interrupted} unfinished download(s) from the last run marked as failed (retry them in the app)");
    }
    let pruned = db.prune_failed_downloads()?;
    if pruned > 0 {
        tracing::info!("removed {pruned} stale failed download record(s) (song already downloaded or failed again later)");
    }

    let wc = worker_config();
    tracing::info!("worker: {} {}", wc.python.display(), wc.script.display());
    let worker = Worker::spawn(wc);

    let http = reqwest::Client::builder()
        .user_agent("Mozilla/5.0 (X11; Linux x86_64) Geonix/0.1")
        .connect_timeout(std::time::Duration::from_secs(15))
        .build()?;

    let state = AppState {
        downloads: DownloadManager::new(db.clone(), worker.clone(), music_dir.clone(), covers_dir.clone()),
        db,
        worker,
        http,
        covers_dir,
        stream_cache: Arc::new(Mutex::new(HashMap::new())),
        recs_lock: Arc::new(tokio::sync::Mutex::new(())),
    };
    tokio::spawn(routes::recommendations::daily_refresh(state.clone()));

    let addr = SocketAddr::from(([127, 0, 0, 1], port));
    let listener = tokio::net::TcpListener::bind(addr).await?;
    tracing::info!("Geonix backend on http://{addr}  data: {}  music: {}", data_dir.display(), music_dir.display());
    axum::serve(listener, routes::router(state))
        .with_graceful_shutdown(shutdown_signal())
        .await?;
    Ok(())
}

/// Ctrl+C or SIGTERM. Returning lets the runtime drop the worker process
/// (it is spawned with kill_on_drop).
async fn shutdown_signal() {
    let ctrl_c = async {
        let _ = tokio::signal::ctrl_c().await;
    };
    #[cfg(unix)]
    let term = async {
        match tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()) {
            Ok(mut s) => {
                s.recv().await;
            }
            Err(_) => std::future::pending::<()>().await,
        }
    };
    #[cfg(not(unix))]
    let term = std::future::pending::<()>();
    tokio::select! {
        _ = ctrl_c => {},
        _ = term => {},
    }
    tracing::info!("shutting down");
    // Open SSE streams would hold graceful shutdown forever; give requests
    // a moment, then exit. The worker quits on its own when its stdin closes.
    tokio::spawn(async {
        tokio::time::sleep(std::time::Duration::from_secs(3)).await;
        std::process::exit(0);
    });
}
