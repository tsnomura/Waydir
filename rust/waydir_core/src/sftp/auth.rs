use std::path::Path;

use russh::keys::{decode_secret_key, load_secret_key, PrivateKey};

pub(super) enum AuthKind {
    Auto,
    Password(String),
    Key {
        path: String,
        passphrase: Option<String>,
    },
}

impl AuthKind {
    pub fn from_ffi(
        kind: u32,
        password: Option<String>,
        key_path: Option<String>,
        passphrase: Option<String>,
    ) -> Self {
        match kind {
            1 => AuthKind::Password(password.unwrap_or_default()),
            2 => AuthKind::Key {
                path: key_path.unwrap_or_default(),
                passphrase,
            },
            _ => AuthKind::Auto,
        }
    }
}

fn first_env(names: &[&str], get: impl Fn(&str) -> Option<String>) -> Option<String> {
    names
        .iter()
        .filter_map(|name| get(name))
        .find(|value| !value.is_empty())
}

fn env(name: &str) -> Option<String> {
    std::env::var(name).ok()
}

fn home_dir_from(get: impl Fn(&str) -> Option<String>) -> Option<String> {
    first_env(&["HOME", "USERPROFILE"], get)
}

fn default_user_from(get: impl Fn(&str) -> Option<String>) -> String {
    first_env(&["USER", "USERNAME", "LOGNAME"], get).unwrap_or_default()
}

pub(super) fn resolve_user(user: String) -> String {
    if user.is_empty() {
        default_user_from(env)
    } else {
        user
    }
}

pub(super) fn discover_default_keys() -> Vec<PrivateKey> {
    let home = match home_dir_from(env) {
        Some(h) => h,
        None => return Vec::new(),
    };
    let candidates = ["id_ed25519", "id_ecdsa", "id_rsa"];
    let mut keys = Vec::new();
    for name in candidates.iter() {
        let p = Path::new(&home).join(".ssh").join(name);
        if !p.exists() {
            continue;
        }
        if let Ok(k) = load_secret_key(&p, None) {
            keys.push(k);
        }
    }
    keys
}

pub(super) fn load_key(path: &str, passphrase: Option<&str>) -> Result<PrivateKey, String> {
    let content = std::fs::read_to_string(path).map_err(|e| format!("read key: {e}"))?;
    decode_secret_key(&content, passphrase).map_err(|e| format!("decode key: {e}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn vars(pairs: &[(&str, &str)]) -> impl Fn(&str) -> Option<String> {
        let map: std::collections::HashMap<String, String> = pairs
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect();
        move |name| map.get(name).cloned()
    }

    #[test]
    fn home_prefers_home_variable() {
        let get = vars(&[("HOME", "/home/a"), ("USERPROFILE", r"C:\Users\b")]);
        assert_eq!(home_dir_from(get), Some("/home/a".into()));
    }

    #[test]
    fn home_falls_back_to_userprofile() {
        let get = vars(&[("USERPROFILE", r"C:\Users\b")]);
        assert_eq!(home_dir_from(get), Some(r"C:\Users\b".into()));
    }

    #[test]
    fn home_skips_empty_values() {
        let get = vars(&[("HOME", ""), ("USERPROFILE", r"C:\Users\b")]);
        assert_eq!(home_dir_from(get), Some(r"C:\Users\b".into()));
    }

    #[test]
    fn home_missing_everywhere() {
        assert_eq!(home_dir_from(vars(&[])), None);
    }

    #[test]
    fn default_user_uses_user_then_username() {
        assert_eq!(
            default_user_from(vars(&[("USER", "a"), ("USERNAME", "b")])),
            "a"
        );
        assert_eq!(default_user_from(vars(&[("USERNAME", "b")])), "b");
        assert_eq!(default_user_from(vars(&[("LOGNAME", "c")])), "c");
        assert_eq!(default_user_from(vars(&[])), "");
    }

    #[test]
    fn resolve_user_keeps_explicit_name() {
        assert_eq!(resolve_user("root".into()), "root");
    }
}
