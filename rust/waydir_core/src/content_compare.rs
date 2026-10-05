use std::ffi::{c_char, CStr};
use std::fs::File;
use std::io::{self, Read};
use std::path::Path;

const CHUNK: usize = 1 << 20;

/// # Safety
/// `left` and `right` must be NUL-terminated C strings.
#[no_mangle]
pub unsafe extern "C" fn waydir_files_equal(left: *const c_char, right: *const c_char) -> i32 {
    if left.is_null() || right.is_null() {
        return -1;
    }
    let left = CStr::from_ptr(left).to_string_lossy().into_owned();
    let right = CStr::from_ptr(right).to_string_lossy().into_owned();
    match files_equal(Path::new(&left), Path::new(&right)) {
        Ok(Some(true)) => 1,
        Ok(Some(false)) => 0,
        Ok(None) | Err(_) => -1,
    }
}

fn files_equal(left: &Path, right: &Path) -> io::Result<Option<bool>> {
    let left_meta = std::fs::metadata(left)?;
    let right_meta = std::fs::metadata(right)?;
    if !left_meta.is_file() || !right_meta.is_file() {
        return Ok(None);
    }
    if is_cloud_placeholder(&left_meta) || is_cloud_placeholder(&right_meta) {
        return Ok(None);
    }
    if left_meta.len() != right_meta.len() {
        return Ok(Some(false));
    }
    let mut a = File::open(left)?;
    let mut b = File::open(right)?;
    let mut buf_a = vec![0u8; CHUNK];
    let mut buf_b = vec![0u8; CHUNK];
    loop {
        let n_a = read_full(&mut a, &mut buf_a)?;
        let n_b = read_full(&mut b, &mut buf_b)?;
        if n_a != n_b || buf_a[..n_a] != buf_b[..n_b] {
            return Ok(Some(false));
        }
        if n_a == 0 {
            return Ok(Some(true));
        }
    }
}

fn read_full(file: &mut File, buf: &mut [u8]) -> io::Result<usize> {
    let mut filled = 0;
    while filled < buf.len() {
        match file.read(&mut buf[filled..]) {
            Ok(0) => break,
            Ok(n) => filled += n,
            Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
            Err(e) => return Err(e),
        }
    }
    Ok(filled)
}

#[cfg(target_os = "windows")]
fn is_cloud_placeholder(meta: &std::fs::Metadata) -> bool {
    use std::os::windows::fs::MetadataExt;
    const OFFLINE: u32 = 0x1000;
    const RECALL_ON_OPEN: u32 = 0x40000;
    const RECALL_ON_DATA_ACCESS: u32 = 0x400000;
    meta.file_attributes() & (OFFLINE | RECALL_ON_OPEN | RECALL_ON_DATA_ACCESS) != 0
}

#[cfg(not(target_os = "windows"))]
fn is_cloud_placeholder(_meta: &std::fs::Metadata) -> bool {
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    fn write(dir: &Path, name: &str, data: &[u8]) -> std::path::PathBuf {
        let path = dir.join(name);
        std::fs::write(&path, data).unwrap();
        path
    }

    #[test]
    fn detects_equal_and_different_content() {
        let dir = std::env::temp_dir().join(format!("wd_cc_{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let a = write(&dir, "a", b"hello world");
        let b = write(&dir, "b", b"hello world");
        let c = write(&dir, "c", b"hello there");
        let d = write(&dir, "d", b"hello");
        assert_eq!(files_equal(&a, &b).unwrap(), Some(true));
        assert_eq!(files_equal(&a, &c).unwrap(), Some(false));
        assert_eq!(files_equal(&a, &d).unwrap(), Some(false));
        assert!(files_equal(&a, &dir.join("missing")).is_err());
        std::fs::remove_dir_all(&dir).unwrap();
    }
}
