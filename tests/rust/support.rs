use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

/// テスト用の一意な一時ディレクトリを作成する。
pub fn make_temp_dir(label: &str) -> PathBuf {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();

    let mut dir = std::env::temp_dir();
    dir.push(format!("fm-test-{}-{}-{}", label, std::process::id(), nanos));
    std::fs::create_dir_all(&dir).unwrap();
    dir
}
