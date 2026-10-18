//! Runs the Python worker as a child process and talks to it with one JSON
//! object per line. Requests carry an `id`; progress events and the final
//! result/error carry the same `id`. If the worker dies it is restarted and
//! every in-flight request fails with an error.

use std::collections::HashMap;
use std::path::PathBuf;
use std::process::Stdio;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use serde::Deserialize;
use serde_json::{json, Value};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::process::Command;
use tokio::sync::{mpsc, oneshot};

use crate::error::ApiError;

#[derive(Debug, Clone, Deserialize)]
pub struct Progress {
    #[serde(default)]
    pub percent: f64,
    #[serde(default)]
    pub speed: Option<String>,
}

#[derive(Debug, Deserialize)]
struct Message {
    id: String,
    #[serde(rename = "type")]
    kind: String,
    #[serde(default)]
    data: Value,
    #[serde(default)]
    message: Option<String>,
    #[serde(default)]
    percent: f64,
    #[serde(default)]
    speed: Option<String>,
}

struct Pending {
    result: oneshot::Sender<Result<Value, String>>,
    progress: Option<mpsc::UnboundedSender<Progress>>,
}

#[derive(Default)]
struct Inner {
    stdin: Mutex<Option<mpsc::UnboundedSender<String>>>,
    pending: Mutex<HashMap<String, Pending>>,
    running: AtomicBool,
}

#[derive(Clone)]
pub struct Worker {
    inner: Arc<Inner>,
}

pub struct WorkerConfig {
    pub python: PathBuf,
    pub script: PathBuf,
}

fn lock<T>(m: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|p| p.into_inner())
}

impl Worker {
    /// Start the supervisor that keeps the worker process alive.
    pub fn spawn(config: WorkerConfig) -> Self {
        let worker = Self { inner: Arc::new(Inner::default()) };
        let inner = worker.inner.clone();
        tokio::spawn(async move { supervise(inner, config).await });
        worker
    }

    pub fn is_running(&self) -> bool {
        self.inner.running.load(Ordering::SeqCst)
    }

    /// Send a command and wait for its result.
    pub async fn request(&self, cmd: Value, timeout: Duration) -> Result<Value, ApiError> {
        self.request_with_progress(cmd, None, timeout).await
    }

    pub async fn request_with_progress(
        &self,
        mut cmd: Value,
        progress: Option<mpsc::UnboundedSender<Progress>>,
        timeout: Duration,
    ) -> Result<Value, ApiError> {
        let id = uuid::Uuid::new_v4().to_string();
        let obj = cmd.as_object_mut().ok_or_else(|| ApiError::internal("worker command must be an object"))?;
        obj.insert("id".into(), json!(id));
        let line = serde_json::to_string(&cmd).map_err(|e| ApiError::internal(e.to_string()))?;

        let (tx, rx) = oneshot::channel();
        lock(&self.inner.pending).insert(id.clone(), Pending { result: tx, progress });

        let sent = lock(&self.inner.stdin).as_ref().map(|s| s.send(line).is_ok()).unwrap_or(false);
        if !sent {
            lock(&self.inner.pending).remove(&id);
            return Err(ApiError::Unavailable("music worker is not running (is Python set up?)".into()));
        }

        match tokio::time::timeout(timeout, rx).await {
            Ok(Ok(Ok(data))) => Ok(data),
            Ok(Ok(Err(message))) => Err(ApiError::Unavailable(message)),
            Ok(Err(_)) => Err(ApiError::Unavailable("music worker stopped unexpectedly".into())),
            Err(_) => {
                lock(&self.inner.pending).remove(&id);
                Err(ApiError::Unavailable("music worker timed out".into()))
            }
        }
    }
}

fn dispatch(inner: &Inner, line: &str) {
    let msg: Message = match serde_json::from_str(line) {
        Ok(m) => m,
        Err(e) => {
            tracing::warn!("ignoring malformed worker line ({e}): {line}");
            return;
        }
    };
    let mut pending = lock(&inner.pending);
    match msg.kind.as_str() {
        "progress" => {
            if let Some(tx) = pending.get(&msg.id).and_then(|p| p.progress.as_ref()) {
                let _ = tx.send(Progress { percent: msg.percent, speed: msg.speed });
            }
        }
        "result" => {
            if let Some(p) = pending.remove(&msg.id) {
                let _ = p.result.send(Ok(msg.data));
            }
        }
        "error" => {
            if let Some(p) = pending.remove(&msg.id) {
                let _ = p.result.send(Err(msg.message.unwrap_or_else(|| "unknown worker error".into())));
            }
        }
        other => tracing::warn!("unknown worker message type {other:?}"),
    }
}

async fn supervise(inner: Arc<Inner>, config: WorkerConfig) {
    let mut backoff = Duration::from_millis(500);
    loop {
        let started = std::time::Instant::now();
        match run_once(&inner, &config).await {
            Ok(status) => tracing::warn!("python worker exited ({status}); restarting"),
            Err(e) => tracing::error!(
                "could not start python worker {} {}: {e}",
                config.python.display(),
                config.script.display()
            ),
        }
        inner.running.store(false, Ordering::SeqCst);
        *lock(&inner.stdin) = None;
        for (_, p) in lock(&inner.pending).drain() {
            let _ = p.result.send(Err("music worker crashed; please try again".into()));
        }
        // Reset the backoff after a long healthy run, grow it on crash loops.
        backoff = if started.elapsed() > Duration::from_secs(30) {
            Duration::from_millis(500)
        } else {
            (backoff * 2).min(Duration::from_secs(30))
        };
        tokio::time::sleep(backoff).await;
    }
}

async fn run_once(inner: &Arc<Inner>, config: &WorkerConfig) -> std::io::Result<std::process::ExitStatus> {
    let mut child = Command::new(&config.python)
        .arg("-u")
        .arg(&config.script)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .kill_on_drop(true)
        .spawn()?;

    let mut stdin = child.stdin.take().ok_or_else(|| std::io::Error::other("no stdin"))?;
    let stdout = child.stdout.take().ok_or_else(|| std::io::Error::other("no stdout"))?;

    let (tx, mut rx) = mpsc::unbounded_channel::<String>();
    *lock(&inner.stdin) = Some(tx);
    inner.running.store(true, Ordering::SeqCst);
    tracing::info!("python worker started (pid {:?})", child.id());

    let writer = tokio::spawn(async move {
        while let Some(line) = rx.recv().await {
            if stdin.write_all(line.as_bytes()).await.is_err()
                || stdin.write_all(b"\n").await.is_err()
                || stdin.flush().await.is_err()
            {
                break;
            }
        }
    });

    let reader_inner = inner.clone();
    let reader = tokio::spawn(async move {
        let mut lines = BufReader::new(stdout).lines();
        while let Ok(Some(line)) = lines.next_line().await {
            if !line.trim().is_empty() {
                dispatch(&reader_inner, &line);
            }
        }
    });

    let status = child.wait().await;
    writer.abort();
    let _ = reader.await;
    status
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dispatch_routes_progress_and_result_by_id() {
        let inner = Inner::default();
        let (rtx, mut rrx) = oneshot::channel();
        let (ptx, mut prx) = mpsc::unbounded_channel();
        lock(&inner.pending).insert("abc".into(), Pending { result: rtx, progress: Some(ptx) });

        dispatch(&inner, r#"{"id":"abc","type":"progress","percent":42.5,"speed":"1.2MiB/s"}"#);
        dispatch(&inner, r#"{"id":"other","type":"result","data":{}}"#);
        dispatch(&inner, "not json");
        let p = prx.try_recv().unwrap();
        assert_eq!(p.percent, 42.5);
        assert_eq!(p.speed.as_deref(), Some("1.2MiB/s"));

        dispatch(&inner, r#"{"id":"abc","type":"result","data":{"ok":true}}"#);
        assert_eq!(rrx.try_recv().unwrap().unwrap(), json!({"ok": true}));
        assert!(lock(&inner.pending).is_empty());
    }

    #[test]
    fn dispatch_delivers_errors() {
        let inner = Inner::default();
        let (rtx, mut rrx) = oneshot::channel();
        lock(&inner.pending).insert("x".into(), Pending { result: rtx, progress: None });
        dispatch(&inner, r#"{"id":"x","type":"error","message":"Video unavailable"}"#);
        assert_eq!(rrx.try_recv().unwrap().unwrap_err(), "Video unavailable");
    }
}
