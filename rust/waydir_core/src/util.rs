use std::ffi::OsStr;

use crate::codec::Entry;

pub(crate) const EXCLUDED: &[&str] = &[
    ".git",
    "node_modules",
    ".cache",
    ".venv",
    "__pycache__",
    "target",
    "build",
    ".gradle",
    ".idea",
];

#[cfg(unix)]
pub(crate) fn os_bytes(s: &OsStr) -> Vec<u8> {
    use std::os::unix::ffi::OsStrExt;
    s.as_bytes().to_vec()
}

#[cfg(not(unix))]
pub(crate) fn os_bytes(s: &OsStr) -> Vec<u8> {
    s.to_string_lossy().into_owned().into_bytes()
}

#[cfg(unix)]
pub(crate) fn path_depth(path: &[u8]) -> usize {
    path.iter().filter(|&&b| b == b'/').count()
}

#[cfg(not(unix))]
pub(crate) fn path_depth(path: &[u8]) -> usize {
    path.iter().filter(|&&b| b == b'/' || b == b'\\').count()
}

pub(crate) fn num_cpus() -> usize {
    std::thread::available_parallelism()
        .map(|n| n.get())
        .unwrap_or(4)
}

pub(crate) fn search_threads() -> usize {
    num_cpus().saturating_sub(1).max(1)
}

pub(crate) fn mtime_ms(meta: &std::fs::Metadata) -> i64 {
    match meta.modified() {
        Ok(t) => match t.duration_since(std::time::UNIX_EPOCH) {
            Ok(d) => d.as_millis() as i64,
            Err(e) => -(e.duration().as_millis() as i64),
        },
        Err(_) => 0,
    }
}

/// Fills `size`/`mtime_ms`/`created_ms`/`added_ms`/`mode`/`uid`/`gid` on `e`
/// from an already-obtained `meta` — for callers that got it "for free"
/// alongside directory enumeration (e.g. Windows' `FindNextFileW`) and would
/// otherwise pay for a redundant stat.
pub(crate) fn apply_metadata(e: &mut Entry, meta: &std::fs::Metadata) {
    e.size = meta.len() as i64;
    e.mtime_ms = mtime_ms(meta);
    e.created_ms = created_ms(meta);
    e.added_ms = added_ms(&e.disk_path, meta);
    fill_owner_mode(e, meta);
}

/// Stats `e.disk_path` itself and fills the same fields as [apply_metadata].
/// Leaves them zeroed (rather than erroring) when the stat fails, so a file
/// that vanished between listing and stat-ing doesn't abort the whole batch.
pub(crate) fn fill_stat(e: &mut Entry) {
    if let Ok(meta) = std::fs::metadata(&e.disk_path) {
        apply_metadata(e, &meta);
    }
}

#[cfg(unix)]
fn created_ms(meta: &std::fs::Metadata) -> i64 {
    use std::os::unix::fs::MetadataExt;
    // Real birth time (statx btime) where the filesystem records it. Some
    // filesystems (older ext4 without crtime, network mounts) have none, so we
    // fall back to ctime to keep the column populated rather than show nothing.
    created_via_btime(meta)
        .unwrap_or_else(|| meta.ctime() * 1000 + (meta.ctime_nsec() / 1_000_000))
}

fn created_via_btime(meta: &std::fs::Metadata) -> Option<i64> {
    use std::time::UNIX_EPOCH;
    meta.created()
        .ok()
        .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
        .map(|d| d.as_millis() as i64)
}

#[cfg(not(unix))]
fn created_ms(meta: &std::fs::Metadata) -> i64 {
    created_via_btime(meta).unwrap_or(0)
}

#[cfg(target_os = "macos")]
fn added_ms(path: &std::path::Path, meta: &std::fs::Metadata) -> i64 {
    read_date_added_xattr(path).unwrap_or_else(|| created_ms(meta))
}

#[cfg(target_os = "macos")]
fn read_date_added_xattr(path: &std::path::Path) -> Option<i64> {
    use std::ffi::{c_char, c_void, CString};
    extern "C" {
        fn getxattr(
            path: *const c_char,
            name: *const c_char,
            value: *mut c_void,
            size: usize,
            position: u32,
            options: i32,
        ) -> isize;
    }
    let path_cstr = CString::new(path.as_os_str().as_encoded_bytes()).ok()?;
    const ATTR: &std::ffi::CStr =
        unsafe { std::ffi::CStr::from_bytes_with_nul_unchecked(b"com.apple.metadata:kMDItemDateAdded\0") };
    let mut buf = [0u8; 64];
    let len = unsafe {
        getxattr(
            path_cstr.as_ptr(),
            ATTR.as_ptr(),
            buf.as_mut_ptr() as *mut c_void,
            buf.len(),
            0,
            0,
        )
    };
    if len < 17 {
        return None;
    }
    if &buf[0..8] != b"bplist00" || buf[8] != 0x33 {
        return None;
    }
    let secs = f64::from_be_bytes(buf[9..17].try_into().ok()?);
    Some(((secs + 978_307_200.0) * 1000.0) as i64)
}

#[cfg(not(target_os = "macos"))]
fn added_ms(_path: &std::path::Path, meta: &std::fs::Metadata) -> i64 {
    created_ms(meta)
}

#[cfg(unix)]
fn fill_owner_mode(e: &mut Entry, meta: &std::fs::Metadata) {
    use std::os::unix::fs::MetadataExt;
    e.mode = meta.mode();
    e.uid = meta.uid();
    e.gid = meta.gid();
}

#[cfg(not(unix))]
fn fill_owner_mode(_e: &mut Entry, _meta: &std::fs::Metadata) {}
