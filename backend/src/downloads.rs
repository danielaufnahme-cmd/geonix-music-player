//! Download queue: at most 3 downloads run at once. Every state change is
//! saved to the database and broadcast to `GET /api/downloads/events`.

use std::path::PathBuf;
use std::sync::Arc;
use std::time::{Duration, Instant};

use serde::Serialize;
use serde_json::json;
use tokio::sync::{broadcast, mpsc, Semaphore};

use crate::db::Db;
use crate::error::{ApiError, ApiResult};
use crate::models::{now_ms, Download, DownloadedTrack, PlaylistInfo, Track};
use crate::worker::Worker;

pub const MAX_PARALLEL: usize = 3;
const DOWNLOAD_TIMEOUT: Duration = Duration::from_secs(30 * 60);
const INFO_TIMEOUT: Duration = Duration::from_secs(120);

#[derive(Clone)]
pub struct DownloadManager {
    db: Arc<Db>,
    worker: Worker,
    permits: Arc<Semaphore>,
    events: broadcast::Sender<Download>,
    music_dir: PathBuf,
    covers_dir: PathBuf,
}

#[derive(Debug, Serialize)]
pub struct PlaylistImport {
    pub playlist_id: i64,
    pub name: String,
    pub total: usize,
    pub queued: usize,
    /// Songs that were already downloaded (added without downloading).
    pub skipped: usize,
    /// Songs that were already in the target playlist (left untouched).
    pub already_in_playlist: usize,
    pub downloads: Vec<Download>,
}

/// Where an import puts the YouTube songs.
pub enum ImportTarget<'a> {
    /// Create a new playlist, named by the user or after the YouTube title.
    New { name: Option<&'a str> },
    /// Append to an existing playlist, keeping its name and current songs.
    Existing(i64),
}

/// Result of placing imported songs into a playlist.
#[derive(Debug, Default, PartialEq)]
struct ImportPlan {
    to_download: Vec<String>,
    in_library: usize,
    already_in_playlist: usize,
}

impl DownloadManager {
    pub fn new(db: Arc<Db>, worker: Worker, music_dir: PathBuf, covers_dir: PathBuf) -> Self {
        let (events, _) = broadcast::channel(256);
        Self { db, worker, permits: Arc::new(Semaphore::new(MAX_PARALLEL)), events, music_dir, covers_dir }
    }

    pub fn subscribe(&self) -> broadcast::Receiver<Download> {
        self.events.subscribe()
    }

    fn save(&self, d: &Download) {
        if let Err(e) = self.db.update_download(d) {
            tracing::error!("saving download {} failed: {e}", d.id);
        }
        let _ = self.events.send(d.clone());
    }

    /// Queue one song. Songs already in the library are reported as
    /// "skipped"; a song that is already queued returns the existing entry.
    pub fn enqueue(&self, video_id: &str, playlist_id: Option<i64>) -> ApiResult<Download> {
        if let Some(active) = self.db.active_download_for(video_id)? {
            return Ok(active);
        }
        let known = self.db.get_track(video_id)?;
        let now = now_ms();
        let mut d = Download {
            id: uuid::Uuid::new_v4().to_string(),
            video_id: video_id.to_string(),
            title: known.as_ref().map(|t| t.title.clone()).unwrap_or_default(),
            artist: known.as_ref().map(|t| t.artist.clone()).unwrap_or_default(),
            status: "queued".into(),
            progress: 0.0,
            speed: None,
            error: None,
            playlist_id,
            created_at: now,
            updated_at: now,
        };

        if has_file(known.as_ref()) {
            d.status = "skipped".into();
            d.progress = 100.0;
            self.db.insert_download(&d)?;
            let _ = self.events.send(d.clone());
            return Ok(d);
        }

        self.db.insert_download(&d)?;
        // A new attempt replaces earlier failures of the same song.
        self.db.delete_failed_for(video_id, &d.id)?;
        let _ = self.events.send(d.clone());
        self.start(d.clone(), known);
        Ok(d)
    }

    pub fn retry(&self, id: &str) -> ApiResult<Download> {
        let mut d = self.db.get_download(id)?.ok_or_else(|| ApiError::not_found("download not found"))?;
        if d.status != "failed" {
            return Err(ApiError::bad_request(format!("download is {}, only failed downloads can be retried", d.status)));
        }
        let known = self.db.get_track(&d.video_id)?;
        d.error = None;
        d.speed = None;
        d.updated_at = now_ms();
        self.db.delete_failed_for(&d.video_id, &d.id)?;
        if has_file(known.as_ref()) {
            // Downloaded in the meantime (e.g. by another attempt).
            d.status = "skipped".into();
            d.progress = 100.0;
            self.save(&d);
            return Ok(d);
        }
        d.status = "queued".into();
        d.progress = 0.0;
        self.save(&d);
        self.start(d.clone(), known);
        Ok(d)
    }

    fn start(&self, d: Download, known: Option<Track>) {
        let this = self.clone();
        tokio::spawn(async move { this.run(d, known).await });
    }

    async fn run(&self, mut d: Download, known: Option<Track>) {
        let Ok(_permit) = self.permits.clone().acquire_owned().await else {
            return;
        };
        d.status = "downloading".into();
        d.updated_at = now_ms();
        self.save(&d);

        // Forward progress events, throttled so the DB isn't hammered.
        let (ptx, mut prx) = mpsc::unbounded_channel::<crate::worker::Progress>();
        let progress_mgr = self.clone();
        let mut progress_dl = d.clone();
        let forwarder = tokio::spawn(async move {
            let mut last = Instant::now() - Duration::from_secs(1);
            while let Some(p) = prx.recv().await {
                progress_dl.progress = p.percent.clamp(0.0, 100.0);
                progress_dl.speed = p.speed;
                if last.elapsed() >= Duration::from_millis(300) {
                    last = Instant::now();
                    progress_dl.updated_at = now_ms();
                    progress_mgr.save(&progress_dl);
                }
            }
        });

        let cmd = json!({
            "cmd": "download",
            "video_id": d.video_id,
            "dest_dir": self.music_dir,
            "covers_dir": self.covers_dir,
            "meta": known,
        });
        let result = self.worker.request_with_progress(cmd, Some(ptx), DOWNLOAD_TIMEOUT).await;
        forwarder.abort();

        d.updated_at = now_ms();
        d.speed = None;
        match result.and_then(|data| {
            serde_json::from_value::<DownloadedTrack>(data)
                .map_err(|e| ApiError::internal(format!("bad download result from worker: {e}")))
        }) {
            Ok(done) => {
                let file = done.track.file_path.clone().unwrap_or_default();
                match self.db.mark_downloaded(&done.track, &file, done.cover_path.as_deref()) {
                    Ok(()) => {
                        if let Err(e) = self.db.delete_failed_for(&d.video_id, &d.id) {
                            tracing::warn!("clearing old failures of {}: {e}", d.video_id);
                        }
                        d.status = "done".into();
                        d.progress = 100.0;
                        d.title = done.track.title.clone();
                        d.artist = done.track.artist.clone();
                        if let Some(pid) = d.playlist_id {
                            // Imported playlists already contain the song; this is a no-op then.
                            if let Err(e) = self.db.add_to_playlist(pid, &d.video_id) {
                                tracing::warn!("adding {} to playlist {pid}: {e}", d.video_id);
                            }
                        }
                    }
                    Err(e) => {
                        d.status = "failed".into();
                        d.error = Some(format!("saving to library failed: {e}"));
                    }
                }
            }
            Err(e) => {
                d.status = "failed".into();
                d.error = Some(e.to_string());
            }
        }
        self.save(&d);
    }

    /// Ask the worker what is in a playlist (used for the preview and import).
    pub async fn playlist_info(&self, url: &str) -> ApiResult<PlaylistInfo> {
        let data = self.worker.request(json!({"cmd": "playlist_info", "url": url}), INFO_TIMEOUT).await?;
        let info: PlaylistInfo = serde_json::from_value(data)
            .map_err(|e| ApiError::internal(format!("bad playlist info from worker: {e}")))?;
        for t in &info.tracks {
            self.db.upsert_track_meta(t)?;
        }
        Ok(info)
    }

    /// Import a YouTube playlist into a new or an existing local playlist.
    /// Songs keep the YouTube order (appended after existing songs), songs
    /// already in the playlist are skipped, songs already downloaded are added
    /// right away, and only the missing ones are queued for download.
    pub async fn enqueue_playlist(&self, url: &str, target: ImportTarget<'_>) -> ApiResult<PlaylistImport> {
        if let ImportTarget::Existing(id) = target {
            self.check_import_target(id)?;
        }
        let info = self.playlist_info(url).await?;
        if info.tracks.is_empty() {
            return Err(ApiError::bad_request("that playlist has no available songs"));
        }
        let (playlist_id, name) = match target {
            ImportTarget::New { name } => {
                let name = playlist_name(name, &info.title);
                (self.db.create_playlist(&name, "imported", Some(url))?, name)
            }
            ImportTarget::Existing(id) => (id, self.db.playlist(id)?.playlist.name),
        };
        let ids: Vec<String> = info.tracks.iter().map(|t| t.video_id.clone()).collect();
        let plan = place_tracks(&self.db, playlist_id, &ids)?;

        let mut downloads = Vec::new();
        for id in &plan.to_download {
            downloads.push(self.enqueue(id, Some(playlist_id))?);
        }
        Ok(PlaylistImport {
            playlist_id,
            name,
            total: ids.len(),
            queued: downloads.len(),
            skipped: plan.in_library,
            already_in_playlist: plan.already_in_playlist,
            downloads,
        })
    }

    /// Existing playlists can receive imports, except the generated Discover Mix.
    fn check_import_target(&self, id: i64) -> ApiResult<()> {
        let playlist = match self.db.playlist(id) {
            Ok(p) => p.playlist,
            Err(rusqlite::Error::QueryReturnedNoRows) => {
                return Err(ApiError::not_found(format!("playlist {id} not found")))
            }
            Err(e) => return Err(e.into()),
        };
        if playlist.kind == "discover" {
            return Err(ApiError::bad_request("the Discover Mix is generated automatically; import into another playlist"));
        }
        Ok(())
    }
}

/// Append `ids` (in order) to a playlist, skipping songs it already has.
/// Returns which songs still need downloading.
fn place_tracks(db: &Db, playlist_id: i64, ids: &[String]) -> ApiResult<ImportPlan> {
    let mut seen: std::collections::HashSet<String> =
        db.playlist(playlist_id)?.tracks.into_iter().map(|t| t.video_id).collect();
    let mut plan = ImportPlan::default();
    for id in ids {
        if !seen.insert(id.clone()) {
            plan.already_in_playlist += 1;
            continue;
        }
        db.add_to_playlist(playlist_id, id)?;
        if has_file(db.get_track(id)?.as_ref()) {
            plan.in_library += 1;
        } else {
            plan.to_download.push(id.clone());
        }
    }
    Ok(plan)
}

/// The user's name for an imported playlist, or the YouTube title if blank.
fn playlist_name(custom: Option<&str>, youtube_title: &str) -> String {
    match custom.map(str::trim) {
        Some(n) if !n.is_empty() => n.chars().take(120).collect(),
        _ => youtube_title.to_string(),
    }
}

/// True when the song is in the library and its MP3 is still on disk.
fn has_file(track: Option<&Track>) -> bool {
    track
        .and_then(|t| t.file_path.as_ref())
        .map(|p| std::path::Path::new(p).exists())
        .unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn playlist_name_prefers_custom_name() {
        assert_eq!(playlist_name(Some("  Road trip "), "YT Title"), "Road trip");
        assert_eq!(playlist_name(Some("   "), "YT Title"), "YT Title");
        assert_eq!(playlist_name(None, "YT Title"), "YT Title");
        assert_eq!(playlist_name(Some(&"x".repeat(300)), "t").len(), 120);
    }

    #[test]
    fn has_file_requires_existing_mp3() {
        let dir = std::env::temp_dir().join(format!("geonix-hasfile-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&dir).unwrap();
        let mp3 = dir.join("song.mp3");
        std::fs::write(&mp3, b"id3").unwrap();
        let mut t = Track { video_id: "a".into(), title: "A".into(), ..Default::default() };
        assert!(!has_file(None));
        assert!(!has_file(Some(&t)));
        t.file_path = Some(mp3.to_string_lossy().into_owned());
        assert!(has_file(Some(&t)));
        std::fs::remove_file(&mp3).unwrap();
        assert!(!has_file(Some(&t)), "a deleted file must be downloaded again");
        std::fs::remove_dir_all(dir).ok();
    }

    fn library_track(db: &Db, dir: &std::path::Path, id: &str) {
        let mp3 = dir.join(format!("{id}.mp3"));
        std::fs::write(&mp3, b"id3").unwrap();
        let t = Track { video_id: id.into(), title: id.into(), ..Default::default() };
        db.mark_downloaded(&t, &mp3.to_string_lossy(), None).unwrap();
    }

    fn remote_track(db: &Db, id: &str) {
        db.upsert_track_meta(&Track { video_id: id.into(), title: id.into(), ..Default::default() }).unwrap();
    }

    fn playlist_ids(db: &Db, id: i64) -> Vec<String> {
        db.playlist(id).unwrap().tracks.into_iter().map(|t| t.video_id).collect()
    }

    #[test]
    fn import_into_existing_playlist_appends_in_order_and_skips_present_songs() {
        let dir = std::env::temp_dir().join(format!("geonix-import-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&dir).unwrap();
        let db = Db::open_in_memory().unwrap();
        library_track(&db, &dir, "mine");
        library_track(&db, &dir, "have");
        for id in ["y1", "y3"] {
            remote_track(&db, id);
        }
        let p = db.create_playlist("smal", "user", None).unwrap();
        db.add_to_playlist(p, "mine").unwrap();

        // YouTube order: y1, mine (already in playlist), have (downloaded), y3
        let ids = ["y1", "mine", "have", "y3"].map(String::from);
        let plan = place_tracks(&db, p, &ids).unwrap();

        assert_eq!(playlist_ids(&db, p), ["mine", "y1", "have", "y3"]);
        assert_eq!(plan.already_in_playlist, 1);
        assert_eq!(plan.in_library, 1);
        assert_eq!(plan.to_download, ["y1", "y3"]);
        assert_eq!(db.playlist(p).unwrap().playlist.name, "smal");

        // Importing the same playlist again changes nothing.
        let again = place_tracks(&db, p, &ids).unwrap();
        assert_eq!(again.already_in_playlist, 4);
        assert!(again.to_download.is_empty());
        assert_eq!(playlist_ids(&db, p), ["mine", "y1", "have", "y3"]);
        std::fs::remove_dir_all(dir).ok();
    }

    #[test]
    fn import_into_new_playlist_keeps_youtube_order() {
        let dir = std::env::temp_dir().join(format!("geonix-import-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&dir).unwrap();
        let db = Db::open_in_memory().unwrap();
        library_track(&db, &dir, "b");
        remote_track(&db, "a");
        remote_track(&db, "c");
        let p = db.create_playlist("Levels", "imported", None).unwrap();
        let plan = place_tracks(&db, p, &["a", "b", "c"].map(String::from)).unwrap();
        assert_eq!(playlist_ids(&db, p), ["a", "b", "c"]);
        assert_eq!(plan, ImportPlan { to_download: vec!["a".into(), "c".into()], in_library: 1, already_in_playlist: 0 });
        std::fs::remove_dir_all(dir).ok();
    }
}
