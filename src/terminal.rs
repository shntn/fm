use crossterm::event::{self, Event, KeyCode, KeyEvent, KeyModifiers};
use crossterm::terminal;

/// rawモードのDropガード。
pub struct RawModeGuard;

impl RawModeGuard {
    pub fn new() -> Result<Self, std::io::Error> {
        terminal::enable_raw_mode()?;
        Ok(RawModeGuard)
    }
}

impl Drop for RawModeGuard {
    fn drop(&mut self) {
        let _ = terminal::disable_raw_mode();
    }
}

/// KeyCode → Lua キー名のテーブル。
/// 追加はここに1行足すだけでよい。
static KEY_TABLE: &[(KeyCode, &str)] = &[
    // 方向キー
    (KeyCode::Up,           "up"),
    (KeyCode::Down,         "down"),
    (KeyCode::Left,         "left"),
    (KeyCode::Right,        "right"),
    // 編集キー
    (KeyCode::Enter,        "enter"),
    (KeyCode::Tab,          "tab"),
    (KeyCode::BackTab,      "shift-tab"),
    (KeyCode::Backspace,    "backspace"),
    (KeyCode::Delete,       "delete"),
    (KeyCode::Insert,       "insert"),
    // ナビゲーション
    (KeyCode::Home,         "home"),
    (KeyCode::End,          "end"),
    (KeyCode::PageUp,       "pageup"),
    (KeyCode::PageDown,     "pagedown"),
    // ファンクションキー
    (KeyCode::F(1),         "f1"),
    (KeyCode::F(2),         "f2"),
    (KeyCode::F(3),         "f3"),
    (KeyCode::F(4),         "f4"),
    (KeyCode::F(5),         "f5"),
    (KeyCode::F(6),         "f6"),
    (KeyCode::F(7),         "f7"),
    (KeyCode::F(8),         "f8"),
    (KeyCode::F(9),         "f9"),
    (KeyCode::F(10),        "f10"),
    (KeyCode::F(11),        "f11"),
    (KeyCode::F(12),        "f12"),
    // その他
    (KeyCode::Esc,          "escape"),
    (KeyCode::Null,         "null"),
];

/// Ctrl+文字 → Lua キー名（"ctrl-a" 〜 "ctrl-z"）
fn ctrl_key_name(c: char) -> Option<String> {
    if c.is_ascii_alphabetic() {
        Some(format!("ctrl-{}", c.to_ascii_lowercase()))
    } else {
        // ctrl-space など一部の記号
        match c {
            ' ' => Some("ctrl-space".to_string()),
            _ => None,
        }
    }
}

/// Alt+文字 → Lua キー名（"alt-a" など）
fn alt_key_name(c: char) -> Option<String> {
    Some(format!("alt-{}", c))
}

pub fn read_key() -> Option<String> {
    loop {
        let ev = event::read().ok()?;
        if let Event::Key(KeyEvent { code, modifiers, .. }) = ev {
            // Ctrl+C は強制終了
            if code == KeyCode::Char('c') && modifiers.contains(KeyModifiers::CONTROL) {
                std::process::exit(0);
            }

            // テーブル駆動変換
            for (kc, name) in KEY_TABLE {
                if code == *kc {
                    return Some(name.to_string());
                }
            }

            // 印字可能文字（修飾キーなし or Shift のみ）
            if let KeyCode::Char(c) = code {
                let ctrl  = modifiers.contains(KeyModifiers::CONTROL);
                let alt   = modifiers.contains(KeyModifiers::ALT);

                if ctrl {
                    if let Some(name) = ctrl_key_name(c) {
                        return Some(name);
                    }
                } else if alt {
                    if let Some(name) = alt_key_name(c) {
                        return Some(name);
                    }
                } else {
                    // 通常文字（Shiftは文字自体に反映済み）
                    return Some(c.to_string());
                }
            }

            // 未知のキーは無視してループ継続
        }
        // Resize等のイベントも無視
    }
}