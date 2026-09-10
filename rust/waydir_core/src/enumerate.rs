use std::ffi::{c_char, CStr};
use std::sync::Mutex;

use ignore::WalkState;

use crate::codec::{finish_buffer, serialise, Entry};
use crate::util::{apply_metadata, os_bytes, path_depth};
use crate::walker::{base_builder, EntrySink};

/// Recursively enumerates everything under `root` (the root itself is not
/// included). Hidden files are always included and nothing is excluded.
/// When `postorder` is true the result is ordered deepest-path-first so a
/// caller can unlink children before their parents (delete pre-scans).
/// `with_stat` fills in real size/mtime/created/added/mode/uid/gid instead of
/// leaving them zero (copy pre-scans, which need real sizes for progress and
/// conflict comparisons) — pulled from the same directory-entry metadata the
/// parallel walk already touches, which costs nothing extra on Windows
/// (`FindNextFileW` already returns it) and one extra stat per entry
/// elsewhere. Same buffer contract as the other entry points.
///
/// # Safety
/// `root` must be a valid NUL-terminated C string; `out_len` writable.
#[no_mangle]
pub unsafe extern "C" fn waydir_enumerate(
    root: *const c_char,
    postorder: bool,
    with_stat: bool,
    out_len: *mut usize,
) -> *mut u8 {
    if root.is_null() || out_len.is_null() {
        return std::ptr::null_mut();
    }
    let root = match CStr::from_ptr(root).to_str() {
        Ok(s) => s.to_owned(),
        Err(_) => return std::ptr::null_mut(),
    };

    let buckets: Mutex<Vec<Vec<Entry>>> = Mutex::new(Vec::new());
    let mut builder = base_builder(&root);
    if with_stat {
        // Copy pre-scans want to walk straight through a reparse point (a
        // symlink, junction, or cloud-sync placeholder) and copy what's
        // really inside it, not stop at the reparse point itself. `walkdir`
        // (which `ignore` wraps) tracks visited directories by file id to
        // detect cycles, so a genuinely circular symlink still terminates.
        // Delete pre-scans (with_stat: false) deliberately keep the default
        // of not following, so deleting a reparse point never reaches into
        // — let alone deletes — whatever it points at.
        builder.follow_links(true);
    }

    let walker = builder.build_parallel();
    walker.run(|| {
        let mut sink = EntrySink {
            local: Vec::new(),
            buckets: &buckets,
        };
        Box::new(move |result| {
            let dirent = match result {
                Ok(d) => d,
                Err(_) => return WalkState::Continue,
            };
            if dirent.depth() == 0 {
                return WalkState::Continue;
            }
            let is_dir = dirent.file_type().map(|t| t.is_dir()).unwrap_or(false);
            let mut entry = Entry {
                is_dir,
                size: 0,
                mtime_ms: 0,
                created_ms: 0,
                added_ms: 0,
                mode: 0,
                uid: 0,
                gid: 0,
                name: os_bytes(dirent.file_name()),
                path: os_bytes(dirent.path().as_os_str()),
                disk_path: dirent.path().to_path_buf(),
            };
            if with_stat {
                if let Ok(meta) = dirent.metadata() {
                    apply_metadata(&mut entry, &meta);
                }
            }
            sink.local.push(entry);
            WalkState::Continue
        })
    });

    let mut entries: Vec<Entry> = buckets
        .into_inner()
        .unwrap()
        .into_iter()
        .flatten()
        .collect();
    if postorder {
        // Deepest first by component count, not byte length: byte length can
        // place a parent before its own child and break unlink order.
        entries.sort_by(|a, b| {
            path_depth(&b.path)
                .cmp(&path_depth(&a.path))
                .then_with(|| b.path.cmp(&a.path))
        });
    }

    finish_buffer(serialise(&entries), out_len)
}
