use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Duration;

use once_cell::sync::Lazy;
use russh::client::{self, Handle};
use russh::keys::{PrivateKey, PrivateKeyWithHashAlg, PublicKey};
use russh_sftp::client::{RawSftpSession, SftpSession};
use russh_sftp::protocol::{Packet, StatusCode};
use tokio::sync::Mutex;

use super::auth::{discover_default_keys, load_key, resolve_user, AuthKind};
use super::runtime::rt;

/// Status zwracany do Darta po próbie otwarcia sesji.
#[repr(u32)]
#[derive(Clone, Copy, Debug)]
pub enum SftpOpenStatus {
    Ok = 0,
    AuthRequired = 1,
    Error = 2,
}

const POSIX_RENAME: &str = "posix-rename@openssh.com";

pub(super) struct Client {
    pub(super) _ssh: Handle<ClientHandler>,
    pub(super) sftp: SftpSession,
    posix_rename: Option<Option<RawSftpSession>>,
}

impl Client {
    pub(super) async fn rename(&mut self, from: &str, to: &str) -> Result<(), String> {
        if self.posix_rename.is_none() {
            self.posix_rename = Some(open_posix_rename(&self._ssh).await);
        }
        let Some(Some(raw)) = &self.posix_rename else {
            return self
                .sftp
                .rename(from, to)
                .await
                .map_err(|e| format!("rename: {e}"));
        };
        let mut data = Vec::with_capacity(8 + from.len() + to.len());
        for s in [from, to] {
            data.extend_from_slice(&(s.len() as u32).to_be_bytes());
            data.extend_from_slice(s.as_bytes());
        }
        match raw.extended(POSIX_RENAME, data).await {
            Ok(Packet::Status(status)) if status.status_code == StatusCode::Ok => Ok(()),
            Ok(Packet::Status(status)) => Err(format!("rename: {}", status.error_message)),
            Ok(_) => Err("rename: unexpected reply".into()),
            Err(e) => Err(format!("rename: {e}")),
        }
    }
}

async fn open_posix_rename(ssh: &Handle<ClientHandler>) -> Option<RawSftpSession> {
    let channel = ssh.channel_open_session().await.ok()?;
    channel.request_subsystem(true, "sftp").await.ok()?;
    let raw = RawSftpSession::new(channel.into_stream());
    let version = raw.init().await.ok()?;
    (version.extensions.get(POSIX_RENAME).map(String::as_str) == Some("1")).then_some(raw)
}

pub(super) struct ClientHandler;

impl client::Handler for ClientHandler {
    type Error = russh::Error;

    fn check_server_key(
        &mut self,
        _server_public_key: &PublicKey,
    ) -> impl std::future::Future<Output = Result<bool, Self::Error>> + Send {
        async { Ok(true) }
    }
}

#[derive(Eq, PartialEq, Hash, Clone)]
pub(super) struct SessionKey {
    pub host: String,
    pub port: u16,
    pub user: String,
}

pub(super) struct Pool {
    pub sessions: HashMap<u64, Arc<Mutex<Client>>>,
    pub by_key: HashMap<SessionKey, u64>,
}

static POOL: Lazy<Mutex<Pool>> = Lazy::new(|| {
    Mutex::new(Pool {
        sessions: HashMap::new(),
        by_key: HashMap::new(),
    })
});
static NEXT_ID: AtomicU64 = AtomicU64::new(1);

pub(super) async fn get(id: u64) -> Option<Arc<Mutex<Client>>> {
    let pool = POOL.lock().await;
    pool.sessions.get(&id).cloned()
}

pub(super) async fn open(
    host: String,
    port: u16,
    user: String,
    auth: AuthKind,
) -> Result<(SftpOpenStatus, u64, String), String> {
    let user = resolve_user(user);
    let key = SessionKey {
        host: host.clone(),
        port,
        user: user.clone(),
    };
    {
        let pool = POOL.lock().await;
        if let Some(id) = pool.by_key.get(&key).copied() {
            if pool.sessions.contains_key(&id) {
                return Ok((SftpOpenStatus::Ok, id, String::new()));
            }
        }
    }

    let config = Arc::new(client::Config {
        inactivity_timeout: Some(Duration::from_secs(60 * 60)),
        ..Default::default()
    });
    let mut handle = client::connect(config, (host.as_str(), port), ClientHandler)
        .await
        .map_err(|e| format!("connect: {e}"))?;

    let auth_ok = try_authenticate(&mut handle, &user, &auth).await?;
    if !auth_ok {
        return Ok((SftpOpenStatus::AuthRequired, 0, "auth required".into()));
    }

    let channel = handle
        .channel_open_session()
        .await
        .map_err(|e| format!("channel: {e}"))?;
    channel
        .request_subsystem(true, "sftp")
        .await
        .map_err(|e| format!("subsystem: {e}"))?;
    let sftp = SftpSession::new(channel.into_stream())
        .await
        .map_err(|e| format!("sftp init: {e}"))?;

    let id = NEXT_ID.fetch_add(1, Ordering::Relaxed);
    let client = Arc::new(Mutex::new(Client {
        _ssh: handle,
        sftp,
        posix_rename: None,
    }));
    let mut pool = POOL.lock().await;
    pool.sessions.insert(id, client);
    pool.by_key.insert(key, id);
    Ok((SftpOpenStatus::Ok, id, String::new()))
}

async fn try_authenticate(
    handle: &mut Handle<ClientHandler>,
    user: &str,
    auth: &AuthKind,
) -> Result<bool, String> {
    match auth {
        AuthKind::Password(password) => handle
            .authenticate_password(user, password)
            .await
            .map(|result| result.success())
            .map_err(|e| format!("auth password: {e}")),
        AuthKind::Key { path, passphrase } => {
            let key = load_key(path, passphrase.as_deref())?;
            authenticate_key(handle, user, key).await
        }
        AuthKind::Auto => {
            for key in discover_default_keys() {
                match authenticate_key(handle, user, key).await {
                    Ok(true) => return Ok(true),
                    Ok(false) => continue,
                    Err(_) => continue,
                }
            }
            Ok(false)
        }
    }
}

async fn authenticate_key(
    handle: &mut Handle<ClientHandler>,
    user: &str,
    key: PrivateKey,
) -> Result<bool, String> {
    let hash_alg = handle
        .best_supported_rsa_hash()
        .await
        .map_err(|e| format!("auth key: {e}"))?
        .flatten();
    handle
        .authenticate_publickey(user, PrivateKeyWithHashAlg::new(Arc::new(key), hash_alg))
        .await
        .map(|result| result.success())
        .map_err(|e| format!("auth key: {e}"))
}

pub(super) async fn close(id: u64) {
    let mut pool = POOL.lock().await;
    pool.by_key.retain(|_, v| *v != id);
    pool.sessions.remove(&id);
}

pub(super) fn block<F, T>(f: F) -> T
where
    F: std::future::Future<Output = T>,
{
    rt().block_on(f)
}
